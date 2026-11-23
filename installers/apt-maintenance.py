"""Maintain the dedicated stable APT installation of MyEasyToolkit."""

import contextlib
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import tempfile


APP = 'myeasytoolkit'
RING = 'myeasytoolkit-archive-keyring'
SOURCE = Path('/etc/apt/sources.list.d/myeasytoolkit.list')
KEY = Path('/usr/share/keyrings/myeasytoolkit-archive-keyring.gpg')
BINARY = Path('/usr/bin/myeasytoolkit')
README = Path('/usr/share/doc/myeasytoolkit/README.md')
JOURNAL = Path('/var/lib/myeasytoolkit-apt-removal.json')
STATUS = Path('/var/lib/dpkg/status')
LISTS = Path('/var/lib/apt/lists')
ARCHIVES = Path('/var/cache/apt/archives')
MAX_AGE = timedelta(days=90)
ENV = {'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'LC_ALL': 'C'}
# These packages have no application state or maintainer scripts to clean up.
PAYLOAD = {BINARY: APP, README: APP, KEY: RING}


def fail(message):
    raise RuntimeError(message)


def run(*args, capture=False, check=True, env=None, **options):
    return subprocess.run(
        [str(arg) for arg in args], check=check, text=True, env=env or ENV,
        stdout=subprocess.PIPE if capture else None, **options,
    )


def output(*args, **options):
    return run(*args, capture=True, **options).stdout.strip()


def mounts():
    return {
        Path(re.sub(r'\\([0-7]{3})', lambda match: chr(int(match[1], 8)), line.split()[4]))
        for line in Path('/proc/self/mountinfo').read_text().splitlines()
    }


def inspect(path, *, directory=False):
    """Accept only root-controlled regular files and real parent directories."""
    for parent in reversed(path.parents):
        info = parent.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid or info.st_mode & 0o022:
            fail(f'Répertoire parent non sûr ou lien symbolique. {parent}')
    try:
        info = path.lstat()
    except FileNotFoundError:
        return None
    valid_type = stat.S_ISDIR if directory else stat.S_ISREG
    if (not valid_type(info.st_mode) or info.st_uid or info.st_mode & 0o022
            or (not directory and info.st_nlink != 1)):
        fail(f'Type, propriétaire, permissions ou liens inattendus. {path}')
    return info


def managed_file(path, mounted):
    if path in mounted:
        fail(f'Point de montage à vérifier. {path}')
    return inspect(path)


def unlink(path):
    with contextlib.suppress(FileNotFoundError):
        path.unlink()


def identity(info):
    return [info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_gid,
            info.st_size, info.st_mtime_ns, info.st_ctime_ns]


def digest(path):
    sha = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(65536), b''):
            sha.update(chunk)
    return sha.hexdigest()


def private_lock(path, flock):
    inspect(path)
    fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    lock = fcntl.flock if flock else fcntl.lockf
    try:
        lock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        os.close(fd)
        fail(f'Une opération est déjà en cours. {path}')
    return os.fdopen(fd, 'wb')


def sources_and_config():
    defaults = {
        'ROOT': ('RootDir', '/'),
        'CONF': ('Dir::Etc::sourcelist/f', '/etc/apt/sources.list'),
        'PARTS': ('Dir::Etc::sourceparts/d', str(SOURCE.parent)),
        'TRUST': ('Dir::Etc::trusted/f', '/etc/apt/trusted.gpg'),
        'KEYS': ('Dir::Etc::trustedparts/d', '/etc/apt/trusted.gpg.d'),
        'STATUS': ('Dir::State::status/f', str(STATUS)),
        'LISTS': ('Dir::State::lists/d', str(LISTS)),
        'ARCHIVES': ('Dir::Cache::archives/d', str(ARCHIVES)),
    }
    args = [arg for name, (option, _) in defaults.items() for arg in (name, option)]
    settings = dict(line.rstrip(';').split('=', 1) for line in output(
        'apt-config', 'shell', *args,
    ).splitlines())
    for name, (_, expected) in defaults.items():
        value = shlex.split(settings.get(name, shlex.quote(expected)))[0]
        if Path(value) != Path(expected):
            fail(f'Configuration APT non standard à vérifier. {name}={value}')
    if not inspect(SOURCE.parent, directory=True):
        fail(f'Répertoire de sources APT absent. {SOURCE.parent}')
    return [Path(defaults['CONF'][1]), *SOURCE.parent.glob('*.list'),
            *SOURCE.parent.glob('*.sources')]


def check_owner(path, package=None):
    result = run('dpkg-query', '-S', path, capture=True, stderr=subprocess.PIPE, check=False)
    if result.returncode == 1 and not result.stdout:
        return
    owners = result.stdout.splitlines()
    if result.returncode or len(owners) != 1 or package is None or not re.fullmatch(
        re.escape(package) + r'(?::[a-z0-9-]+)?: ' + re.escape(str(path)), owners[0],
    ):
        fail(f'Fichier déclaré par un autre paquet ou détourné. {path}')


def source_line(repo, arch, key):
    return f'deb [arch={arch} signed-by={key}] {repo} stable main\n'


def configuration(repo):
    mounted = mounts()
    if SOURCE.parent in mounted or KEY.parent in mounted:
        fail('Un répertoire de configuration APT est monté séparément.')
    source = managed_file(SOURCE, mounted)
    key = managed_file(KEY, mounted)
    check_owner(SOURCE)
    check_owner(KEY, RING)
    if source:
        # The first releases did not specify an architecture.
        historical = (r'deb\s+\[(?:arch=(?:amd64|arm64)\s+)?signed-by='
                      + re.escape(str(KEY)) + r'\]\s+' + re.escape(repo)
                      + r'/?\s+stable\s+main')
        active = [line.split('#', 1)[0].strip() for line in SOURCE.read_text().splitlines()]
        if not re.fullmatch(historical, ' '.join(line for line in active if line)) or sum(
            bool(line) for line in active
        ) != 1:
            fail(f'Source APT dédiée à vérifier. {SOURCE}')
    for path in sources_and_config():
        if path == SOURCE:
            continue
        info = inspect(path)
        if info is None:
            continue
        if info.st_size > 1024 * 1024:
            fail(f'Source APT trop volumineuse pour être vérifiée. {path}')
        data = '\n'.join(line.split('#', 1)[0] for line in path.read_text().splitlines())
        host = re.escape(repo.split('/')[2])
        if re.search(r'https?://' + host + r'(?::[0-9]+)?/apt(?=[/\s]|$)(?!/[\w.-])',
                     data, re.I):
            fail(f'Une autre source utilise le dépôt MyEasyToolkit. {path}')
        for name in re.findall(r'''(?<![\w:/])(/[^\s\[\](),"';=]+)''', data):
            if Path(name).resolve() in (KEY, SOURCE):
                fail(f'Une autre source référence le trousseau ou la source. {path}')
        if re.search(r'signed-by[^\n]*[\\%]', data, re.I):
            fail(f'Référence APT ambiguë. {path}')
    trusted = Path('/etc/apt/trusted.gpg')
    trusted_parts = Path('/etc/apt/trusted.gpg.d')
    aliases = [trusted]
    if inspect(trusted_parts, directory=True):
        aliases.extend(trusted_parts.glob('*'))
    if any(alias.resolve() == KEY for alias in aliases):
        fail('Le trousseau MyEasyToolkit est référencé dans la confiance APT globale.')
    return {
        path: identity(info) if info else None
        for path, info in ((SOURCE, source), (KEY, key))
    }


def package_state(package):
    value = output('dpkg-query', '-W', '-f=${db:Status-Abbrev}\t${Version}', package,
                   stderr=subprocess.DEVNULL, check=False)
    if not value:
        return 'n', ''
    status, _, version = value.partition('\t')
    return status[1], version


def apt_options(source, lists):
    return (
        '-o', f'Dir::Etc::sourcelist={source}', '-o', 'Dir::Etc::sourceparts=-',
        '-o', f'Dir::State::lists={lists}', '-o', 'Dir::Cache::pkgcache=',
        '-o', 'Dir::Cache::srcpkgcache=', '-o', 'APT::Update::Error-Mode=any',
        '-o', 'Acquire::AllowInsecureRepositories=false',
        '-o', 'Acquire::AllowDowngradeToInsecureRepositories=false',
        '-o', 'APT::Get::AllowUnauthenticated=false', '-o', 'Acquire::Check-Date=true',
        '-o', 'Acquire::Check-Valid-Until=true',
        '-o', f'Acquire::Max-ValidTime={int(MAX_AGE.total_seconds())}',
    )


def verify_release(work, key, release, primary, signer):
    clear = work / 'Release'
    unlink(clear)
    status = output('gpgv', '--homedir', work, '--status-fd', '1', '--keyring', key,
                    '--output', clear, release)
    signatures = [line.split() for line in status.splitlines() if line.startswith('[GNUPG:] VALIDSIG ')]
    if (len(signatures) != 1 or signatures[0][2] != signer or signatures[0][-1] != primary
            or re.search(r'\b(EXPKEYSIG|EXPSIG|REVKEYSIG|BADSIG|ERRSIG)\b', status)):
        fail('La signature APT ne correspond pas aux empreintes officielles.')
    fields = dict(re.findall(r'^([\w-]+): (.+)$', clear.read_text(), re.M))
    if any(fields.get(name) != value for name, value in (
        ('Origin', 'MyEasyToolkit'), ('Suite', 'stable'), ('Codename', 'stable'),
    )):
        fail('Identité ou canal inattendu dans l’index APT.')
    now = datetime.now(timezone.utc)
    date = parsedate_to_datetime(fields.get('Date', ''))
    if date.tzinfo is None or not now - MAX_AGE <= date <= now + timedelta(seconds=10):
        fail('Date de publication de l’index APT hors de la période acceptée.')
    if 'Valid-Until' in fields:
        expiry = parsedate_to_datetime(fields['Valid-Until'])
        if expiry.tzinfo is None or now >= expiry:
            fail('L’index APT a expiré.')


def fetch_release(work, base, arch, primary, signer, key_hash):
    if not all(re.fullmatch(pattern, value) for pattern, value in (
        (r'[A-F0-9]{40}', primary), (r'[A-F0-9]{40}', signer), (r'[a-f0-9]{64}', key_hash),
    )):
        fail('Empreintes officielles manquantes dans le lanceur.')
    key = work / KEY.name
    run('curl', '-q', '--fail', '--silent', '--show-error', '--location', '--proto', '=https',
        '--proto-redir', '=https', '--max-time', '60', '--max-filesize', '1048576',
        '--output', key, base + '/apt/' + KEY.name)
    if digest(key) != key_hash:
        fail('Le trousseau téléchargé diffère du trousseau public officiel.')
    key.chmod(0o644)
    source = work / SOURCE.name
    source.write_text(source_line(base + '/apt', arch, key))
    lists = work / 'lists'
    lists.mkdir(mode=0o755)
    options = apt_options(source, lists)
    run('apt-get', *options, 'update')
    indexes = list(lists.glob('*_InRelease'))
    if len(indexes) != 1 or not list(lists.glob(f'*_binary-{arch}_Packages*')):
        fail('Un index APT signé et les listes de paquets sont requis.')
    verify_release(work, key, indexes[0], primary, signer)
    return indexes[0], options


class ArchiveUnavailable(RuntimeError):
    pass


def download(work, options, package, version, arch):
    with tempfile.TemporaryDirectory(dir=work) as directory:
        folder = Path(directory)
        request = package + ('=' + version if version else '')
        result = run('apt-get', *options, '--print-uris', 'download', request,
                     cwd=folder, capture=True, check=False)
        if result.returncode:
            raise ArchiveUnavailable(f'Version absente du dépôt signé. {request}')
        uris = result.stdout.strip().splitlines()
        fields = shlex.split(uris[0]) if len(uris) == 1 else []
        if len(fields) != 4 or not re.fullmatch(r'SHA256:[a-f0-9]{64}', fields[3]):
            fail(f'Somme SHA-256 absente des listes APT. {request}')
        apt_user = pwd.getpwnam('_apt')
        os.chown(folder, apt_user.pw_uid, apt_user.pw_gid)
        run('apt-get', *options, '-o', 'APT::Sandbox::User=_apt', 'download', request, cwd=folder)
        os.chown(folder, 0, 0)
        files = list(folder.glob('*.deb'))
        if len(files) != 1 or not stat.S_ISREG(files[0].lstat().st_mode):
            fail(f'Téléchargement APT incomplet. {package}')
        archive = work / (package + '.deb')
        shutil.copyfile(files[0], archive)
        if digest(archive) != fields[3].split(':')[1]:
            fail(f'Somme de contrôle du paquet incorrecte. {package}')
        metadata = {field: output('dpkg-deb', '-f', archive, field)
                    for field in ('Package', 'Version', 'Architecture')}
        if (metadata['Package'] != package or (version and metadata['Version'] != version)
                or metadata['Architecture'] != ('all' if package == RING else arch)):
            fail(f'Archive de paquet inattendue. {package}')
        if not version:
            _, installed_version = package_state(package)
            if installed_version and run('dpkg', '--compare-versions', metadata['Version'], 'lt',
                                         installed_version, check=False).returncode == 0:
                fail(f'La version publiée de {package} est antérieure à la version locale.')
        return archive


def package_payload(package):
    return [path for path, owner in PAYLOAD.items() if owner == package]


def verified(package):
    paths = package_payload(package)
    if any(not path.is_file() or stat.S_IMODE(path.stat().st_mode) != (0o755 if path == BINARY else 0o644)
           for path in paths):
        return False
    # dpkg --verify is silent when neither the package nor its database entry
    # carries checksums. Older MyEasyToolkit packages used this layout.
    sums = run('dpkg-query', '--control-show', package, 'md5sums',
               capture=True, stderr=subprocess.DEVNULL, check=False)
    names = set(re.findall(r'^[a-f0-9]{32}  (.+)$', sums.stdout, re.M))
    if not all(str(path.relative_to('/')) in names for path in paths):
        return False
    return not re.search(r'^(?!.*\s+c\s).+', output('dpkg', '--verify', package), re.M)


def archive_payload(work, archive, package):
    extracted = work / ('payload-' + package)
    run('dpkg-deb', '-x', archive, extracted)
    paths = {path: extracted / path.relative_to('/') for path in package_payload(package)}
    for path in paths.values():
        if not path.is_file() or path.is_symlink():
            fail(f'Fichier attendu absent du paquet signé. {path.name}')
    return paths


def atomic_write(path, data, mode=0o644, owner=(0, 0)):
    fd, name = tempfile.mkstemp(prefix='.myeasytoolkit-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            os.fchown(stream.fileno(), *owner)
            os.fchmod(stream.fileno(), mode)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
        sync_directory(path.parent)
    finally:
        unlink(Path(name))


def sync_directory(path):
    fd = os.open(str(path), os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def validate_payload():
    current_mounts = mounts()
    if README.parent in current_mounts:
        fail(f'Répertoire documentaire monté séparément. {README.parent}')
    for path, package in PAYLOAD.items():
        if path.parent.is_symlink():
            fail(f'Répertoire de paquet lié. {path.parent}')
        if path.parent.exists():
            managed_file(path, current_mounts)
        check_owner(path, package)


def maintain(mode, base, primary, signer, key_hash, arch):
    repo = base + '/apt'
    before = configuration(repo)
    validate_payload()
    if mode == 'repair' and all(package_state(package)[0] in ('n', 'c') for package in (APP, RING)):
        fail('Aucun paquet MyEasyToolkit à réparer. Lancez l’installation.')
    with tempfile.TemporaryDirectory(prefix='myeasytoolkit-apt-', dir='/tmp') as directory:
        work = Path(directory)
        work.chmod(0o755)
        release, options = fetch_release(work, base, arch, primary, signer, key_hash)
        print('Dépôt APT et signature vérifiés.', flush=True)
        dpkg_options = ('--force-confold',) if mode == 'repair' else ()
        with private_lock(STATUS.parent / 'lock-frontend', False):
            dpkg_env = dict(ENV, DPKG_FRONTEND_LOCKED='true')
            if before != configuration(repo):
                fail('La configuration APT a changé pendant la vérification.')
            validate_payload()
            requested = {}
            for package in (RING, APP):
                state, version = package_state(package)
                if mode == 'repair' and state in ('U', 'F'):
                    run('dpkg', *dpkg_options, '--configure', package, env=dpkg_env, check=False)
                    state, version = package_state(package)
                if mode == 'repair' and state == 'i' and verified(package):
                    if package == APP:
                        continue
                    if digest(KEY) == key_hash:
                        continue
                    # An authorised transition ring may differ from the bootstrap
                    # key. Check it against the keyring package from the signed index.
                requested[package] = version if mode == 'repair' and state not in ('n', 'c') else ''
            packages = {}
            payload = {}
            for package, version in requested.items():
                try:
                    archive = download(work, options, package, version, arch)
                    contents = archive_payload(work, archive, package)
                    if package == RING:
                        try:
                            verify_release(work, contents[KEY], release, primary, signer)
                        except (RuntimeError, subprocess.CalledProcessError) as error:
                            raise ArchiveUnavailable('Version du trousseau antérieure à la rotation.') from error
                except ArchiveUnavailable:
                    if package != RING or not version:
                        raise
                    # The keyring is updated when the recorded version predates
                    # a rotation. Application repair always keeps its version.
                    archive = download(work, options, package, '', arch)
                    shutil.rmtree(work / ('payload-' + package), ignore_errors=True)
                    contents = archive_payload(work, archive, package)
                    verify_release(work, contents[KEY], release, primary, signer)
                packages[package] = archive
                payload.update(contents)
            if before != configuration(repo):
                fail('La source ou le trousseau a changé pendant le téléchargement.')
            validate_payload()
            key_info = KEY.stat() if before[KEY] else None
            saved_key = KEY.read_bytes() if key_info else None
            source_info = SOURCE.stat() if before[SOURCE] else None
            old_source = SOURCE.read_bytes() if source_info else None
            source_changed = False
            try:
                for package, archive in packages.items():
                    run('dpkg', *dpkg_options, '--unpack', archive, env=dpkg_env)
                    run('dpkg', *dpkg_options, '--configure', package, env=dpkg_env)
                validate_payload()
                for package in (RING, APP):
                    paths = package_payload(package)
                    intact = (
                        all(path.is_file() and digest(path) == digest(payload[path]) for path in paths)
                        if package in packages else verified(package)
                    )
                    if package_state(package)[0] != 'i' or not intact:
                        fail(f'Intégrité ou configuration du paquet à vérifier. {package}')
                verify_release(work, KEY, release, primary, signer)
                if mode == 'repair':
                    version = output('runuser', '-u', 'nobody', '--', BINARY, '--version', timeout=15)
                    help_text = output('runuser', '-u', 'nobody', '--', BINARY, '--help', timeout=15)
                    if not version.startswith(APP + ' ') or 'Usage' not in help_text:
                        fail('La CLI MyEasyToolkit a renvoyé une réponse inattendue.')
                    print(version)
                source_bytes = source_line(repo, arch, KEY).encode()
                if old_source != source_bytes:
                    source_changed = True
                    atomic_write(SOURCE, source_bytes)
                # Populate only the project lists so a broken unrelated source
                # does not affect the operation or lose its cached indexes.
                run('apt-get', *apt_options(SOURCE, LISTS), '-o', 'APT::Get::List-Cleanup=0', 'update')
            except (Exception, KeyboardInterrupt):
                if source_changed:
                    if old_source is None:
                        unlink(SOURCE)
                    else:
                        atomic_write(SOURCE, old_source, stat.S_IMODE(source_info.st_mode),
                                     (source_info.st_uid, source_info.st_gid))
                if key_info is None:
                    unlink(KEY)
                elif not KEY.exists() or KEY.read_bytes() != saved_key or KEY.stat().st_mode != key_info.st_mode:
                    atomic_write(KEY, saved_key, stat.S_IMODE(key_info.st_mode),
                                 (key_info.st_uid, key_info.st_gid))
                raise
    print('Opération terminée. Lancez myeasytoolkit.')


def residual_plan(repo, hashes):
    files = configuration(repo)
    validate_payload()
    mounted = mounts()
    for path, approved in hashes.items():
        if path.parent.exists():
            info = managed_file(path, mounted)
            if info and (package_state(APP)[0] not in ('n', 'c') or digest(path) in approved):
                files[path] = identity(info)
            elif info:
                print(f'Fichier conservé, appartenance non établie. {path}')
    for path in LISTS.glob('packages.myeasytoolkit.com_apt_dists_stable_*'):
        if re.fullmatch(r'packages\.myeasytoolkit\.com_apt_dists_stable_(?:InRelease|Release(?:\.gpg)?|main_binary-(?:amd64|arm64)_Packages(?:\.[a-z0-9]+)?)', path.name):
            info = managed_file(path, mounted)
            if info:
                check_owner(path)
                files[path] = identity(info)
    for path in ARCHIVES.glob('myeasytoolkit*.deb'):
        name = re.fullmatch(r'(myeasytoolkit(?:-archive-keyring)?)_[A-Za-z0-9+.~%:-]+_(all|amd64|arm64)\.deb', path.name)
        if name:
            info = managed_file(path, mounted)
            metadata = output('dpkg-deb', '-f', path, 'Package', 'Architecture',
                              stderr=subprocess.DEVNULL, check=False)
            if info and metadata.splitlines() == [f'Package: {name[1]}', f'Architecture: {name[2]}']:
                check_owner(path)
                files[path] = identity(info)
    return {str(path): info for path, info in files.items() if info}


def confirm():
    try:
        terminal = open('/dev/tty', 'r', encoding='utf-8')
    except OSError:
        fail('Ouvrez un terminal interactif pour confirmer la purge.')
    with terminal:
        for word, prompt in (
            ('OUI', 'Confirmer le plan en tapant OUI'),
            ('PURGER', 'Autoriser la purge définitive en tapant PURGER'),
        ):
            print(prompt, flush=True)
            if terminal.readline().rstrip('\r\n') != word:
                print('Purge annulée.')
                return False
    return True


def uninstall(repo, hashes):
    mounted = mounts()
    info = managed_file(JOURNAL, mounted)
    if info and (stat.S_IMODE(info.st_mode) != 0o600 or info.st_size > 1024 * 1024):
        fail(f'Journal de purge à vérifier. {JOURNAL}')
    files = residual_plan(repo, hashes)
    packages = [package for package in (APP, RING) if package_state(package)[0] != 'n']
    if info:
        print('Reprise d’une purge MyEasyToolkit interrompue.')
        saved = json.loads(JOURNAL.read_text())
        if not set(packages).issubset(saved['packages']) or any(
            saved['files'].get(path) != stamp for path, stamp in files.items()
        ):
            fail('Le plan a changé depuis la confirmation. Examinez le journal avant de reprendre.')
        # A file from the plan can cease to be recognised after dpkg purges
        # its ownership record. Verify each surviving inode before resuming.
        for name, stamp in saved['files'].items():
            path = Path(name)
            current = managed_file(path, mounted) if path.parent.exists() else None
            if current and identity(current) != stamp:
                fail(f'Fichier modifié depuis la confirmation. {path}')
            if current:
                files[name] = stamp
    if not files and not packages and not info:
        print('Aucun paquet ni résidu MyEasyToolkit reconnu.')
        return
    print('Aperçu de la purge MyEasyToolkit')
    for package in packages:
        print(f'  Paquet {package}')
    for path in sorted(files):
        print(f'  Fichier {path}')
    if not confirm():
        return
    with private_lock(STATUS.parent / 'lock-frontend', False):
        after = residual_plan(repo, hashes)
        if any(files.get(path) != stamp for path, stamp in after.items()) or packages != [
            package for package in (APP, RING) if package_state(package)[0] != 'n'
        ]:
            fail('Le plan a changé après l’aperçu. Relancez la désinstallation.')
        mounted = mounts()
        for name, stamp in files.items():
            path = Path(name)
            current = managed_file(path, mounted) if path.parent.exists() else None
            if not current or identity(current) != stamp:
                fail(f'Fichier modifié depuis l’aperçu. {path}')
        if not info:
            atomic_write(JOURNAL, json.dumps({'packages': packages, 'files': files}).encode(), 0o600)
        if packages:
            run('dpkg', '--purge', *packages, env=dict(ENV, DPKG_FRONTEND_LOCKED='true'))
            if any(package_state(package)[0] != 'n' for package in packages):
                fail('Purge de paquets incomplète. Relancez la désinstallation.')
        configuration(repo)
        for name, stamp in files.items():
            path = Path(name)
            current = managed_file(path, mounts()) if path.parent.exists() else None
            if current:
                if identity(current) != stamp:
                    fail(f'Fichier modifié pendant la purge. {path}')
                check_owner(path)
                path.unlink()
                sync_directory(path.parent)
        JOURNAL.unlink()
        sync_directory(JOURNAL.parent)
    print('Purge MyEasyToolkit terminée.')


def main():
    mode, base, primary, signer, key_hash, binary_hashes, readme_hashes = sys.argv[1:]
    if os.geteuid() != 0:
        fail('Cette opération APT nécessite les droits administrateur.')
    arch = output('dpkg', '--print-architecture')
    if arch not in ('amd64', 'arm64'):
        fail(f'Architecture Debian non prise en charge. {arch}')
    os.umask(0o022)
    with private_lock(Path('/run/myeasytoolkit-apt.lock'), True):
        if mode == 'uninstall':
            uninstall(base + '/apt', {BINARY: binary_hashes.split(','), README: readme_hashes.split(',')})
        else:
            if managed_file(JOURNAL, mounts()):
                fail('Une purge MyEasyToolkit est en cours. Relancez la désinstallation pour la terminer.')
            maintain(mode, base, primary, signer, key_hash, arch)


def interrupt(_number, _frame):
    raise KeyboardInterrupt


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, interrupt)
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, KeyboardInterrupt) as error:
        sys.exit(f'Opération APT MyEasyToolkit interrompue. {error}')
