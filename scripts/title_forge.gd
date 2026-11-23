class_name TitleForge
extends RefCounted
## The zasuul (wrestler's herald) announces winners with grand titles.
## Real champions collect LONG titles, e.g. Bayanmunkh was called
## "The Perfect among Ten Thousand" and "The Great Flame".
## Here the title grows with each win and is built from HOW you played.
##
## Later: save titles in MongoDB (via the Express server) so they carry over
## between game sessions and grow forever.

## Real state ranks, from small to big.
const RANKS := ["Nachin (Falcon)", "Khartsaga (Hawk)", "Zaan (Elephant)", "Arslan (Lion)", "Avarga (Titan)"]

const STYLE_WORDS := {
	"palm_saves": ["Never-Kneeler", "Palm of Iron", "Grass-Refuser"],
	"pushes_landed": ["Thunder-Shover", "Ger-Toppler", "Wind-Pusher"],
	"ring_out": ["Field-Clearer", "Sender to the Next Valley"],
	"default": ["Mighty One", "Dusty One", "Unshaken One", "Mutton-Powered One"],
}

const PLACES := ["of the Thousand Steppes", "of the Dusty Ring", "Beloved by Marmots",
		"Whose Shadow Scares Yaks", "Fed on Khuushuur", "Who Eats Aaruul Without Water"]


## wins: how many rounds this player has won so far (1, 2, 3...)
## stats: the player's stats dictionary from player.gd
static func forge(wins: int, stats: Dictionary, by_ring_out := false) -> String:
	var rank: String = RANKS[clampi(wins - 1, 0, RANKS.size() - 1)]
	var key := "default"
	if by_ring_out:
		key = "ring_out"
	elif stats.get("palm_saves", 0) > 0:
		key = "palm_saves"
	elif stats.get("pushes_landed", 0) >= 3:
		key = "pushes_landed"
	var words: Array = STYLE_WORDS[key]
	var title := "%s, the %s" % [rank, words.pick_random()]
	if wins >= 2:
		title += ", " + PLACES.pick_random()
	return title
