#!/usr/bin/env ruby
# frozen_string_literal: true

# These examples show to modify Scenario 2 in different ways.
# If you want to run this example, comment out the block at the bottom
# then add e.g. AllHeroes.run

require_relative "../lib/bandit_kings"

GAO_QIU_ID = 0
STARTING_HERO_IDS = [4, 5, 1, 6, 2, 3, 10].freeze
NPC_IDS = [9, 16, 12].freeze

# ---------------------------------------------------------------------------
# Add smithy + shipyard to every prefecture.
# ---------------------------------------------------------------------------
class AllFacilitiesAllPrefectures < BanditKings::ScenarioScript
  def defaults
    {input: "SUIDATA2.CIM", output: "SUIDATA2_ALL_FACILITIES.CIM"}
  end

  def apply(editor)
    editor.add_all_facilities
  end
end

# ---------------------------------------------------------------------------
# Activate every hero and strip allegiance from non-rulers.
# ---------------------------------------------------------------------------
class AllHeroes < BanditKings::ScenarioScript
  def defaults
    {input: "SUIDATA2.CIM", output: "SUIDATA2_ALL_HEROES.CIM"}
  end

  def apply(editor)
    editor.activate_all_heroes(body: 100)
    ruler_ids = editor.prefecture_ruler_ids
    (0...BanditKings::HERO_COUNT).each do |id|
      next if editor.ruler?(id)
      next if ruler_ids.include?(id)

      editor.make_town_person(id)
    end
  end
end

# ---------------------------------------------------------------------------
# Move the 7 starting heroes to clean prefectures.
# ---------------------------------------------------------------------------
class SpreadStartingHeroes < BanditKings::ScenarioScript
  TARGET_PREFECTURES = [1, 3, 22, 44, 41, 40, 16].freeze

  def defaults
    {input: "SUIDATA2.CIM", output: "SUIDATA2_SPREAD_HEROES.CIM"}
  end

  def apply(editor)
    STARTING_HERO_IDS.each_with_index do |leader_id, i|
      editor.move_leader_to_prefecture(leader_id, TARGET_PREFECTURES[i])
    end
    editor.set_leader_table(STARTING_HERO_IDS + [255])
  end
end

# ---------------------------------------------------------------------------
# Demote the 3 NPC leaders to regular heroes and empty their faction slots.
# ---------------------------------------------------------------------------
class DemoteNPCs < BanditKings::ScenarioScript
  def defaults
    {input: "SUIDATA2.CIM", output: "SUIDATA2_DEMOTE_NPCS.CIM"}
  end

  def apply(editor)
    NPC_IDS.each do |id|
      editor.release_followers(id)
      editor.make_town_person(id, prefecture_id: editor.hero_prefecture(id))
    end
    editor.set_leader_table(STARTING_HERO_IDS + [255])
  end
end

if __FILE__ == $PROGRAM_NAME
  puts "This file is a collection of example mods to Scenario 2. Add ExampleClass.run and comment this block to run it."
end
