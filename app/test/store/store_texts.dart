import 'dart:ui';

/// What a store picture says above its screen.
///
/// [headline] always takes two lines, broken where the `\n` is; [subline] at most two,
/// balanced. Store texts, not UI texts: they live here and not in the ARB files, which
/// hold what the app itself shows.
class const StoreText(
  final String pill,
  final String headline,
  final String subline,
);

/// The colour of the dot in each picture's label, one per scene.
const storeAccents = [
  Color(0xFF3B6939),
  Color(0xFF1F6FB2),
  Color(0xFFC2185B),
  Color(0xFFB3541E),
  Color(0xFF7B4FA8),
  Color(0xFF3B6939),
];

/// The six pictures' texts by language, in the order of `storeScenes`.
const storeTexts = <String, List<StoreText>>{
  'de': [
    StoreText(
      'Start',
      'Der Familienalltag –\nbei euch zu Hause',
      'Termine, Aufgaben und Wiki – Self-Hosted.',
    ),
    StoreText(
      'Projekte',
      'Große Aufgaben,\nSchritt für Schritt',
      'Vom ersten Angebot bis fertig: Karten einfach weiterschieben.',
    ),
    StoreText(
      'Kalender',
      'Ein Kalender für\ndie ganze Familie',
      'Schule, Arbeit, Training – jeder in seiner Farbe.',
    ),
    StoreText(
      'Rezepte',
      'Rezepte und\nWissen der Familie',
      'Ob Router-Setup oder Omas Klassiker – alles an einem Ort.',
    ),
    StoreText(
      'Freigabe',
      'Jeder sieht, was er\nsehen soll',
      'Kinder haken ab, Erwachsene schreiben mit.',
    ),
    StoreText(
      'Datenschutz',
      'Eure Daten bleiben\nbei euch, auch offline',
      'Ohne Cloud, ohne Werbung – mit täglicher Sicherung.',
    ),
  ],
  'en': [
    StoreText(
      'Home',
      'Family life –\nright at home',
      'Events, tasks and wiki – self-hosted.',
    ),
    StoreText(
      'Projects',
      'Big plans,\nstep by step',
      'From the first quote to done: just move the cards along.',
    ),
    StoreText(
      'Calendar',
      'One calendar for\nthe whole family',
      'School, work, practice – everyone in their own color.',
    ),
    StoreText(
      'Recipes',
      'The family’s recipes\nand know-how',
      'From the router setup to Grandma’s classics – all in one place.',
    ),
    StoreText(
      'Sharing',
      'Everyone sees\nwhat’s meant for them',
      'Kids tick things off, grown-ups help write.',
    ),
    StoreText(
      'Privacy',
      'Your data stays\nwith you, offline too',
      'No cloud, no ads – with daily backups.',
    ),
  ],
};

/// The Play feature graphic's texts by language.
const featureTexts = <String, ({String tagline, String areas})>{
  'de': (
    tagline: 'Das Self-Hosted-Familien-Tool',
    areas: 'Kalender · Aufgaben · Wiki',
  ),
  'en': (
    tagline: 'The self-hosted family app',
    areas: 'Calendar · Tasks · Wiki',
  ),
};
