# upgrade_skip_prosperity.gd
# ---------------------------------------------------------------------------
# A free LevelUpUpgrade offered whenever the player can't (or doesn't want
# to) pay the ore cost for any of the other level-up choices.
#
# Mechanically it just grants a small permanent Luck bonus ("Prosperity"),
# making future level-up rolls skew toward higher rarities. Thematically it
# represents the player spending this level exploring/prospecting instead of
# forging — an investment in future opportunities rather than raw power.
#
# Always free (metal_cost stays empty) so it's always a valid fallback.
# ---------------------------------------------------------------------------
class_name UpgradeSkipProsperity
extends LevelUpUpgrade

## Amount of permanent Luck granted per skip.
const PROSPERITY_AMOUNT: float = 1.0

static func build() -> UpgradeSkipProsperity:
	var u := UpgradeSkipProsperity.new()
	u.display_name = "Prosperity"
	u.description  = "Skip this level's upgrades.\n+%s Luck (permanent)." % \
		_format_amount(PROSPERITY_AMOUNT)
	u.rarity       = Util.Rarity.COMMON
	return u

func apply(player: CharacterBody2D) -> void:
	player.stats.luck += PROSPERITY_AMOUNT

static func _format_amount(val: float) -> String:
	if float(int(val)) == val:
		return "%d" % int(val)
	return "%.2f" % val
