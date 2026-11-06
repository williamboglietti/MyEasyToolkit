---
name: MyEasyToolkit
description: Page d’installation et de découverte de MyEasyToolkit.
colors:
  ink: "#101828"
  muted: "#475467"
  blue: "#145ce5"
  line: "#dce3ee"
  surface: "#f5f8fc"
  dark: "#101a2d"
  hero: "#17345d"
  white: "#fff"
  hero-text: "#e1ebfa"
  cyan: "#81d2d9"
  cyan-hover: "#b3e8e9"
  cyan-ink: "#102a41"
  usage: "#edf4ff"
  copy-ink: "#114dbb"
  copy-border: "#a8bde0"
  copy-hover: "#e9f1ff"
  focus: "#73a5ff"
  success: "#175b3c"
typography:
  display:
    fontFamily: 'system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif'
    fontSize: "clamp(2.6rem, 4.3vw, 4.15rem)"
    lineHeight: "1.06"
    letterSpacing: "-.035em"
  headline:
    fontFamily: 'system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif'
    fontSize: "clamp(2rem, 3vw, 2.8rem)"
    lineHeight: "1.15"
    letterSpacing: "-.03em"
  body:
    fontFamily: 'system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif'
    lineHeight: "1.55"
  code:
    fontFamily: "ui-monospace, SFMono-Regular, Consolas, monospace"
    fontSize: ".86rem"
    lineHeight: "1.5"
rounded:
  copy: "7px"
  action: "8px"
  command: "9px"
  card: "14px"
spacing:
  small: "12px"
  card: "24px"
  section: "64px"
components:
  button-primary:
    backgroundColor: "{colors.cyan}"
    textColor: "{colors.cyan-ink}"
    rounded: "{rounded.action}"
    padding: "11px 18px"
  button-primary-hover:
    backgroundColor: "{colors.cyan-hover}"
  button-copy:
    backgroundColor: "{colors.white}"
    textColor: "{colors.copy-ink}"
    rounded: "{rounded.copy}"
    padding: "7px 12px"
  button-copy-hover:
    backgroundColor: "{colors.copy-hover}"
  card-platform:
    backgroundColor: "{colors.white}"
    rounded: "{rounded.card}"
    padding: "24px"
---

# Design System: MyEasyToolkit

## Overview

La page utilise les conventions familières d’une page de téléchargement : présentation concise, commandes directement accessibles et illustration du terminal. Le champ bleu marine, les surfaces claires et les contrôles arrondis donnent une identité logicielle sobre. Ringover est la référence de qualité choisie pour cette page.

Ces descriptions traduisent la réalisation actuelle ; elles ne constituent pas un vocabulaire de marque supplémentaire validé par le propriétaire.

## Colors

Le bleu marine structure l’introduction, le cyan met en avant son action et le bleu soutient la navigation et la marque. Le texte sombre et les surfaces blanches ou bleu-gris assurent la lisibilité du contenu. La section d’utilisation est sur fond bleu pâle. Le vert est réservé au message de statut de copie.

## Typography

La page utilise la pile système pour les textes et une pile monospace pour le terminal et les commandes. Les titres principaux utilisent une taille fluide et un interlettrage resserré ; les textes descriptifs restent lisibles à une hauteur de ligne de 1,55. L’illustration du terminal utilise `.88rem/1.75`, réduit à `.76rem` sur petit écran.

## Layout

Le conteneur mesure au maximum 1200px avec 24px de marge latérale, réduite à 16px à 520px et moins. Le héros, les plateformes et la section d’utilisation utilisent deux colonnes, puis une seule à 800px et moins. À 520px et moins, la commande et son bouton s’empilent, les cartes passent à 18px de marge intérieure et le dernier lien de navigation est masqué.

## Elevation & Depth

Les cartes de plateforme restent plates, délimitées par une bordure. L’illustration du terminal se détache par l’ombre `0 16px 38px #00000026` ; les fonds colorés distinguent les sections.

## Shapes

Les cartes et le terminal ont un rayon de 14px. Les zones de commande et les actions utilisent des rayons plus modestes de 7 à 9px. Les cartes et le bouton de copie ont une bordure fine.

## Components

- **Action principale :** lien cyan à texte sombre, en gras, avec 11px × 18px de marge intérieure ; le survol éclaircit le fond.
- **Copie :** bouton blanc bordé, texte bleu et état de survol bleu pâle. Un message associé confirme la copie ou explique la copie manuelle.
- **Carte de plateforme :** fond blanc, bordure bleu-gris, rayon de 14px et marge intérieure de 24px ; la commande est placée dans une surface bleu-gris pâle.
- **Navigation :** marque et liens sur fond blanc, lien bleu au survol. Les liens et boutons reçoivent un contour de focus visible de 3px avec un décalage de 3px.
- **Terminal :** surface marine sombre avec en-tête séparé, texte monospace et sélection bleue. Il est identifié comme une illustration.

## Do's and Don'ts

### Do

- **Do** conserver les commandes lisibles et copiables sur les petits écrans.
- **Do** maintenir un focus visible et respecter la préférence de réduction des animations.
- **Do** identifier l’aperçu du terminal comme une illustration.

### Don't

- **Don't** présenter une illustration du terminal comme une capture réelle.
- **Don't** masquer le retour de réussite ou les instructions de copie manuelle.
