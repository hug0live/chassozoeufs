import 'models.dart';

const List<HideSpotDefinition> kHideSpots = [
  HideSpotDefinition(
    id: 'salon-canape',
    area: 'Salon',
    objectLabel: 'sous le canape',
    riddle:
        "Je porte les siestes et les films, mais le secret d'aujourd'hui dort au plus pres du sol, la ou les coussins ne suffisent plus.",
    hint:
        "Regarde sous l'endroit ou l'on s'assoit pour discuter ou regarder un film.",
  ),
  HideSpotDefinition(
    id: 'salon-bibliotheque',
    area: 'Salon',
    objectLabel: 'dans la bibliotheque',
    riddle:
        "Des dizaines de voix silencieuses y vivent dos a dos. L'oeuf se cache la ou les histoires s'alignent sans jamais sortir.",
    hint: "Cherche entre, derriere ou juste sous les livres.",
  ),
  HideSpotDefinition(
    id: 'salon-plaid',
    area: 'Salon',
    objectLabel: 'dans le plaid',
    riddle:
        "Quand le froid approche, on me cherche. Aujourd'hui, ce n'est pas la chaleur que je protege, mais un tresor bien enveloppe.",
    hint: "Souleve le tissu que l'on attrape pour se couvrir dans le salon.",
  ),
  HideSpotDefinition(
    id: 'cuisine-fruits',
    area: 'Cuisine',
    objectLabel: 'pres du panier a fruits',
    riddle:
        "Parmi les couleurs que l'on croque, un intrus ne se mange pas. Il attend a cote de ce qui sent le verger.",
    hint: "Regarde autour du panier ou du saladier de fruits.",
  ),
  HideSpotDefinition(
    id: 'cuisine-torchons',
    area: 'Cuisine',
    objectLabel: 'dans le tiroir a torchons',
    riddle:
        "Le propre y dort bien plie. L'oeuf s'est glisse parmi ce qui essuie sans jamais parler.",
    hint: "Cherche la ou les torchons ou serviettes de cuisine sont ranges.",
  ),
  HideSpotDefinition(
    id: 'cuisine-epices',
    area: 'Cuisine',
    objectLabel: "sur l'etagere a epices",
    riddle:
        "Le curry, le thym et le paprika montent la garde. Le vrai parfum du jour est celui d'un secret immobile.",
    hint: "Regarde pres des petits pots ou moulins d'epices.",
  ),
  HideSpotDefinition(
    id: 'chambre-oreillers',
    area: 'Chambre',
    objectLabel: 'sous les oreillers',
    riddle:
        "Les reves y commencent la tete lourde et le coeur leger. L'oeuf attend la ou l'on pose ses pensees chaque soir.",
    hint: "Souleve doucement les coussins du lit.",
  ),
  HideSpotDefinition(
    id: 'chambre-chevet',
    area: 'Chambre',
    objectLabel: 'dans la table de chevet',
    riddle:
        "Je veille quand la maison se tait. Livre, lampe et mystere se tiennent tout pres de moi.",
    hint: "Cherche pres du meuble a cote du lit.",
  ),
  HideSpotDefinition(
    id: 'sdb-serviettes',
    area: 'Salle de bain',
    objectLabel: 'dans le meuble a serviettes',
    riddle:
        "Ici, le coton attend les gouttes avec patience. Le secret se seche a l'abri de ce qui sert apres le bain.",
    hint: "Regarde la ou les serviettes propres sont pliees.",
  ),
  HideSpotDefinition(
    id: 'sdb-linge',
    area: 'Salle de bain',
    objectLabel: 'dans le panier a linge',
    riddle:
        "Les tissus fatigues s'y retrouvent avant une grande tournee d'eau. L'oeuf s'est glisse dans ce refuge de vetements.",
    hint: "Cherche pres du linge sale.",
  ),
  HideSpotDefinition(
    id: 'garage-etabli',
    area: 'Garage',
    objectLabel: "sur l'etabli",
    riddle:
        "Les tournevis, les vis et les idees de bricolage savent ou me trouver. Le tresor attend la ou l'on repare le monde.",
    hint: "Regarde pres de la surface ou l'on bricole.",
  ),
  HideSpotDefinition(
    id: 'garage-bottes',
    area: 'Garage',
    objectLabel: 'dans les bottes',
    riddle:
        "Quand la terre colle aux semelles, on vient me chercher. Aujourd'hui, une surprise repose la ou les pieds entrent avant le jardin.",
    hint: "Cherche dans ou pres des bottes ou chaussures du garage.",
  ),
  HideSpotDefinition(
    id: 'jardin-pot',
    area: 'Jardin',
    objectLabel: 'dans le pot de fleurs',
    riddle:
        "La terre garde d'ordinaire des racines. Cette fois, elle protege une coquille qui n'attend ni pluie ni soleil.",
    hint: "Regarde dans ou derriere un grand pot.",
  ),
  HideSpotDefinition(
    id: 'jardin-buisson',
    area: 'Jardin',
    objectLabel: 'pres du buisson',
    riddle:
        "Je fais de l'ombre sans etre un mur. L'oeuf s'est blotti la ou les branches basses compliquent le regard.",
    hint: "Cherche sous ou derriere un buisson.",
  ),
  HideSpotDefinition(
    id: 'jardin-banc',
    area: 'Jardin',
    objectLabel: 'sous le banc',
    riddle:
        "On vient a moi pour souffler quelques minutes. Le tresor, lui, n'a pas pris place dessus mais bien plus bas.",
    hint: "Regarde sous l'endroit ou l'on s'assoit dehors.",
  ),
];

final Map<String, HideSpotDefinition> kHideSpotById = {
  for (final spot in kHideSpots) spot.id: spot,
};
