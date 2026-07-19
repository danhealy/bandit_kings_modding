#!/usr/bin/env ruby
# frozen_string_literal: true

# Dan's custom hacked Scenario 2, implemented on top of the generic
# BanditKings::ScenarioEditor. This script reads SUIDATA2.CIM and produces
# SUIDATA2_NEW.CIM.
#
# Run with defaults:
#   ruby examples/dans_custom_scenario/dans_custom_scenario.rb
# Override input/output:
#   ruby examples/dans_custom_scenario/dans_custom_scenario.rb -i other.cim -o my_output.cim
#
# To use this scenario, please replace SUIDATA2.CIM in your /Data folder with
# the output of this scenario.  It must be named SUIDATA2.CIM.  Then start the
# game as usual, selecting scenario 2.
#
# =============================================================================
# Scenario specification
# =============================================================================
#
# In this scenario, the 7 selectable starting heroes + 4 NPC faction leaders are
# settled out on the map along the edges.  None of them border each other to
# start.  All of the heroes in the game are activated and spread evenly between
# the 11 new faction prefectures, no heroes exist in other prefectures in town.
# The 11 leaders are given boosted stats (depending on their natural style).
# The 11 leaders start with no recruits.
# Gao Qiu is given max stats and 19 other boosted recruits, but his land is
# reduced to just prefecture 23 in the center of the map.
#
# Starting point: the scenario 2 base file SUIDATA2.CIM.
#
# Terminology used throughout the spec:
#
#   * "attributes"  = strength, dexterity, wisdom (the three combat stats).
#   * "persona"     = integrity, mercy, courage (the three personality stats).
#
#   * "ATTR STYLE"  = the ordering of a hero's three attributes from highest
#                     to lowest, written as a 3-letter code. A hero whose
#                     strength > dexterity > wisdom has style "SDW"; one whose
#                     wisdom > strength > dexterity has style "WSD"; and so on.
#   * "PERSONA STYLE" = the same idea applied to integrity/mercy/courage
#                       (e.g. "IMC" for integrity > mercy > courage).
#
# Scenario 2's player-selectable starting heroes are:
#   Lu Zhi Shen, Shi Jin, Song Jiang, Lin Chong, Wu Song, Yang Zhi, Chao Gai.
# In the binary save file these heroes have the IDs
#   STARTING_HERO_IDS = [4, 5, 1, 6, 2, 3, 10]
# (a 0-based ID list; Gao Qiu, the antagonist, is ID 0).
#
# Recipe (each step is implemented in #apply below):
#
#   1.  Every prefecture gets a smithy and a shipyard.
#   2.  All heroes are marked active and reassigned to 100 body points.
#   3.  Excluding Gao Qiu and the 7 starting heroes, rank all other heroes
#       by the sum of their attributes (ties allowed).
#   4.  Take the top 4 heroes from that ranking. Together with the original
#       7 starting heroes, these 11 are the "new faction leaders".
#   5.  Give every new faction leader an attribute style of 100/80/70 and a
#       persona style of 100/95/90, preserving each hero's existing
#       highest->middle->lowest ordering. So a "WSD" hero ends up with
#       wisdom=100, strength=80, dexterity=70; and analogously for persona.
#   6.  Install the 11 new faction leaders in the scenario's leader table
#       (replacing whatever was there before). They must be loyal to
#       themselves, with any previous allegiance removed.
#   7.  Give Gao Qiu 100 body, 100 in every attribute, and 100 in every
#       persona, and place him in prefecture 23.
#   8.  Take the next 19 top-ranked heroes (still excluding Gao Qiu and the
#       11 new faction leaders) and make them 100-loyal recruits of Gao Qiu
#       in prefecture 23, with the same 100/80/70 and 100/95/90 style
#       treatment as the leaders.
#   9.  Settle each of the 11 new faction leaders as the ruler of one of
#       the "new faction prefectures":
#           [1, 3, 6, 22, 34, 48, 44, 41, 40, 16, 14]
#       in that order (leader 0 -> prefecture 1, leader 1 -> prefecture 3,
#       ...). Each of these prefectures is set to:
#           gold 1000, food 1000, metal 0, fur 0,
#           flood 50, land 10, wealth 10, support 0.
#  10.  Every other prefecture (i.e. every prefecture that is not one of
#       the new faction prefectures and not prefecture 23) is reset to:
#           gold 0, food 0, metal 0, fur 0,
#           flood 50, land 10, wealth 10, support 0,
#       and is left unsettled (no ruler).
#  11.  Take every remaining hero (i.e. everyone except Gao Qiu, the 11
#       new faction leaders, and the 19 Gao Qiu recruits) and shuffle them
#       (deterministically, with seed SHUFFLE_SEED so the output is
#       reproducible). Then distribute them evenly, round-robin, across
#       the 11 new faction leaders -- remainders are fine. Each distributed
#       hero becomes a "hero in town" (an unaligned person, allegiance
#       cleared) in the prefecture owned by the leader they were assigned
#       to.
#
# The result is written to SUIDATA2_NEW.CIM in this directory.

require_relative "../../lib/bandit_kings"

module BanditKings
  class DansCustomScenario < ScenarioScript
    # Gao Qiu, the antagonist, is hero ID 0 in the binary save file.
    GAO_QIU_ID = 0

    # The seven scenario-2 starting heroes the player may pick, as 0-based
    # hero IDs: Lu Zhi Shen (4), Shi Jin (5), Song Jiang (1), Lin Chong (6),
    # Wu Song (2), Yang Zhi (3), Chao Gai (10).
    STARTING_HERO_IDS = [4, 5, 1, 6, 2, 3, 10].freeze

    # The eleven prefectures the 11 new faction leaders are assigned to,
    # in the order the leaders are produced (the 7 starting heroes first,
    # then the 4 strongest non-starting, non-Gao-Qiu heroes). Eleven
    # leaders and eleven prefectures, so the lists must stay in lockstep.
    NEW_FACTION_PREFECTURES = [1, 3, 6, 22, 34, 48, 44, 41, 40, 16, 14].freeze

    # The prefecture Gao Qiu and his 19 recruits are gathered in.
    GAO_QIU_PREFECTURE = 23

    # Deterministic seed for the round-robin distribution in step 11.
    # Bumping this changes which hero ends up in which leader's prefecture
    # but leaves everything else identical.
    SHUFFLE_SEED = 42

    def defaults
      project_root = File.expand_path("../..", __dir__)
      {
        input: File.join(project_root, "SUIDATA2.CIM"),
        output: File.join(__dir__, "SUIDATA2_NEW.CIM")
      }
    end

    def apply(editor)
      # ------------------------------------------------------------------
      # Step 1: every prefecture gets a smithy and a shipyard.
      # add_all_facilities ORs SHIPYARD and SMITHY into each prefecture's
      # facility_byte, so prefectures that already had a facility keep it.
      # ------------------------------------------------------------------
      editor.add_all_facilities

      # ------------------------------------------------------------------
      # Step 2: every hero is active and at full body (100). This also
      # resets body2 to 100, since the game uses both a current and a
      # maximum body value.
      # ------------------------------------------------------------------
      editor.activate_all_heroes(body: 100)

      # ------------------------------------------------------------------
      # Steps 3 & 4: pick the 4 strongest non-starting, non-Gao-Qiu heroes
      # as the four new faction leaders, then prepend the seven starting
      # heroes so the 11-member leader list is in "starting heroes first,
      # new picks after" order. The order matters because it lines up
      # with NEW_FACTION_PREFECTURES in step 9.
      #
      # top_heroes_by_attributes sorts by -(str+dex+wis) then by ID, so
      # ties on total attributes are broken by lower hero ID first.
      # ------------------------------------------------------------------
      new_leaders = editor.top_heroes_by_attributes(4, exclude: [GAO_QIU_ID] + STARTING_HERO_IDS)
      leaders = STARTING_HERO_IDS + new_leaders

      puts "Top 4 new faction leaders:"
      new_leaders.each do |id|
        h = editor.hero(id)
        puts "  ID #{id}: #{editor.hero_name(id)} (str=#{h.strength}, dex=#{h.dexterity}, wis=#{h.wisdom})"
      end

      # ------------------------------------------------------------------
      # Step 5: stamp the attribute and persona "styles" onto every one of
      # the 11 leaders. set_hero_attribute_style and set_hero_persona_style
      # look at the hero's current highest->middle->lowest ordering and
      # apply (high, middle, low) in that order, so the original style
      # code (e.g. "WSD") is preserved -- only the magnitudes change.
      # ------------------------------------------------------------------
      leaders.each do |id|
        editor.set_hero_attribute_style(id, high: 100, middle: 80, low: 70)
        editor.set_hero_persona_style(id, high: 100, middle: 95, low: 90)
      end

      # ------------------------------------------------------------------
      # Step 6: rewrite the scenario's leader table to be exactly the
      # 11 new faction leaders (followed by the standard 255 empty-slot
      # sentinel the game uses to mark the end of the table). set_leader_table
      # also recomputes the per-leader flag and D bytes based on whether
      # each leader is already settled in a prefecture -- those flags are
      # finalized in step 9, when each leader is installed as the ruler of
      # a new-faction prefecture.
      #
      # make_ruler (called in step 9) sets the hero's faction to their own
      # ID and loyalty to 0, which is what "loyal to themselves, no
      # previous allegiance" means in the spec.
      # ------------------------------------------------------------------
      editor.set_leader_table(leaders + [255])

      # ------------------------------------------------------------------
      # Step 7: max out Gao Qiu and move him into his stronghold. He keeps
      # his original faction-leader role; he is NOT in the new faction
      # leader table -- he is the antagonist the player faces.
      # ------------------------------------------------------------------
      editor.max_hero_stats(GAO_QIU_ID)
      editor.move_hero(GAO_QIU_ID, GAO_QIU_PREFECTURE)

      # ------------------------------------------------------------------
      # Step 8: take the next 19 strongest heroes (excluding Gao Qiu and
      # the 11 new faction leaders) and turn them into Gao Qiu's personal
      # army in prefecture 23. We ask top_heroes_by_attributes for 19 + 4
      # heroes so that, even after taking the first 19 as recruits, we
      # have 4 left over for the round-robin distribution in step 11.
      # Each recruit gets the same style treatment as a leader, is set
      # to loyalty 100 under Gao Qiu, and is moved to prefecture 23.
      # ------------------------------------------------------------------
      excluded = [GAO_QIU_ID] + leaders
      ranked = editor.top_heroes_by_attributes(19 + 4, exclude: excluded)
      gao_followers = ranked.first(19)
      puts "\n19 Gao Qiu followers: #{gao_followers.join(", ")}"

      gao_followers.each do |id|
        editor.set_hero_attribute_style(id, high: 100, middle: 80, low: 70)
        editor.set_hero_persona_style(id, high: 100, middle: 95, low: 90)
        editor.make_recruit(id, GAO_QIU_ID, loyalty: 100)
        editor.move_hero(id, GAO_QIU_PREFECTURE)
      end

      # ------------------------------------------------------------------
      # Step 9: settle each of the 11 leaders in their assigned
      # prefecture. The leaders and NEW_FACTION_PREFECTURES arrays are
      # parallel: leader i gets NEW_FACTION_PREFECTURES[i].
      #
      # make_ruler marks the hero as ruler (faction = self, loyalty = 0,
      # role nibble 0x03) and installs them as the prefecture's ruler,
      # which also moves the hero into that prefecture.
      # set_prefecture_resources writes the high/low byte pairs for the
      # 16-bit gold/food/metal/fur fields and the single-byte fields
      # directly.
      # ------------------------------------------------------------------
      leaders.each_with_index do |leader_id, i|
        pref_id = NEW_FACTION_PREFECTURES[i]
        editor.make_ruler(leader_id, prefecture_id: pref_id)
        editor.set_prefecture_resources(
          pref_id,
          gold: 1000, food: 1000, metal: 0, fur: 0,
          flood: 50, land: 10, wealth: 10, support: 0
        )
      end

      # ------------------------------------------------------------------
      # Step 10: blank out every prefecture that isn't a new-faction
      # prefecture and isn't Gao Qiu's prefecture. reset_prefecture
      # zeros all resources, sets the neutral land/flood/wealth defaults,
      # and clears the ruler slot so the prefecture is fully unsettled.
      # ------------------------------------------------------------------
      (1..PREFECTURE_COUNT).each do |pid|
        next if NEW_FACTION_PREFECTURES.include?(pid) || pid == GAO_QIU_PREFECTURE

        editor.reset_prefecture(pid)
      end

      # ------------------------------------------------------------------
      # Step 11: round-robin the leftover heroes into the 11 leaders'
      # prefectures. The "protected" set is everyone we've already placed
      # explicitly: Gao Qiu, the 11 leaders, and the 19 Gao Qiu recruits.
      # distribute_heroes shuffles the remaining list with the supplied
      # RNG, then assigns hero i to leader (i mod 11), making each one a
      # town person in that leader's prefecture. make_town_person clears
      # any previous allegiance (faction -> 1, loyalty -> 0) and sets the
      # town-person status bit, which is what "removing their allegiances"
      # and "heroes in town" both mean.
      # ------------------------------------------------------------------
      protected_ids = [GAO_QIU_ID] + leaders + gao_followers
      remaining = (0...HERO_COUNT).to_a.reject { |id| protected_ids.include?(id) }
      distribution = editor.distribute_heroes(remaining, leaders, rng: Random.new(SHUFFLE_SEED))

      puts "\nDistribution of remaining heroes:"
      leaders.each_with_index do |leader_id, i|
        pref_id = NEW_FACTION_PREFECTURES[i]
        count = distribution[leader_id].length
        puts "  #{editor.hero_name(leader_id)} (ID #{leader_id}) -> P#{pref_id}: #{count} town heroes"
      end
    end
  end
end

BanditKings::DansCustomScenario.run if __FILE__ == $PROGRAM_NAME
