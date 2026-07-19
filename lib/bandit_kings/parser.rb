#!/usr/bin/env ruby

# Convenience parser/inspector for Bandit Kings of Ancient China scenario/save
# files. This is a thin wrapper around BanditKings::SaveFile that adds derived
# fields (role, location, active-in-prefecture status) and human-readable output.
#
# The authoritative binary representation lives in lib/bandit_kings/structs.rb;
# this file only adds interpretations and pretty-printing.

require "optparse"
require_relative "structs"

class BanditKingsParser
  attr_reader :filename, :save, :heroes, :prefectures, :version

  def initialize(filename)
    @filename = filename
    @save = BanditKings::SaveFile.read(filename)
    @version = @save.version
    build_prefectures
    build_heroes
  end

  # Build the enriched hero hash used by the test scripts. Values are kept in
  # sync with the underlying structs so callers can still use the old parser
  # interface (hero[:name], hero[:city], etc.).
  def build_heroes
    @heroes = @save.heroes.map.with_index do |h, id|
      entry = @save.hero_name_entries[id]
      {
        id: id,
        offset: BanditKings::HERO_OFFSET + id * BanditKings::HERO_RECORD_SIZE,
        prefix: [h.unknown_0, h.unknown_1, h.unknown_2, h.unknown_3],
        age: h.age,
        faction: h.faction,
        city: h.city,
        body: h.body,
        body2: h.body2,
        integrity: h.integrity,
        mercy: h.mercy,
        courage: h.courage,
        strength: h.strength,
        dexterity: h.dexterity,
        wisdom: h.wisdom,
        loyalty: h.loyalty,
        men: h.men,
        status_byte: h.status_byte,
        has_ship: h.has_ship?,
        active: h.active?,
        raw: [
          h.unknown_0, h.unknown_1, h.unknown_2, h.unknown_3, h.age, h.faction,
          h.city, h.body, h.body2, h.integrity, h.mercy, h.courage, h.strength,
          h.dexterity, h.wisdom, h.unknown_11, h.unknown_12, h.unknown_14,
          h.loyalty, h.unknown_15, h.unknown_16, h.unknown_17, h.men, h.status_byte
        ],
        name: entry.name,
        nickname: entry.nickname,
        can_use_ship: entry.can_use_ship?,
        can_steer: entry.can_steer?,
        role: derive_role(id, h.faction, h.loyalty),
        status: derive_role(id, h.faction, h.loyalty)
      }
    end

    # Location and active-in-prefecture depend on prefectures and all heroes
    # being available, so fill them in now.
    @heroes.each do |h|
      h[:location] = prefecture_by_id(h[:city] + 1)
      h[:active_in_prefecture] = hero_active_in_prefecture?(h)
      h[:exiled] = h[:active] && !h[:active_in_prefecture] && h[:loyalty] > 0
    end
  end

  # Build the enriched prefecture hash. The name is read from the tactical
  # record rather than from a hardcoded list.
  def build_prefectures
    @prefectures = @save.prefecture_records.map.with_index do |pref, i|
      tactical = @save.tactical_records[i]
      {
        id: i + 1,
        name: tactical.name,
        offset: BanditKings::PREFECTURE_RECORD_START + i * BanditKings::PREFECTURE_RECORD_SIZE,
        tactical_offset: BanditKings::TACTICAL_RECORD_START + i * BanditKings::TACTICAL_RECORD_SIZE,
        gold: pref.gold,
        food: pref.food,
        metal: pref.metal,
        fur: pref.fur,
        rate: pref.rate,
        flood: pref.flood,
        land: pref.land,
        wealth: pref.wealth,
        support: pref.support,
        arms: pref.arms,
        skill: pref.skill,
        ruler_id: pref.ruler_id,
        castle_count: tactical.castle_count,
        smithy: tactical.smithy?,
        shipyard: tactical.shipyard?,
        facility_byte: tactical.facility_byte,
        raw: [
          pref.unknown_0, pref.unknown_1, pref.unknown_2, pref.unknown_3,
          pref.unknown_4, pref.unknown_5, pref.unknown_6, pref.unknown_7,
          pref.unknown_8, pref.unknown_9, pref.unknown_10, pref.unknown_11,
          pref.gold_hi, pref.gold_lo, pref.food_hi, pref.food_lo,
          pref.metal_hi, pref.metal_lo, pref.fur_hi, pref.fur_lo,
          pref.rate, pref.flood, pref.land, pref.wealth, pref.support,
          pref.arms, pref.skill, pref.unknown_27, pref.unknown_28,
          pref.unknown_29, pref.unknown_30, pref.ruler_id_plus_one
        ]
      }
    end
  end

  # Derive the hero's role from the faction and loyalty bytes. The active/
  # present flag and exiled status are tracked separately; this method returns
  # only the character's relationship to a faction.
  #
  # Byte 5  = faction ID of the hero's liege (own ID means owner/ruler).
  # Byte 18 = loyalty (0 = unaligned person in town, >0 = recruited by the
  #           faction owner).
  def derive_role(id, faction, loyalty)
    if faction == id
      "Owner/Ruler"
    elsif loyalty > 0
      "Recruited by #{faction_name(faction)}"
    else
      "Person in town"
    end
  end

  def faction_name(faction_id)
    owner_name(faction_id)
  end

  def owner_name(id)
    entry = @save.hero_name_entries[id]
    entry ? entry.name : "hero #{id}"
  end

  def hero_by_id(id)
    @heroes[id]
  end

  def hero_by_name(name)
    @heroes.find { |h| h[:name] == name }
  end

  def prefecture_by_id(id)
    @prefectures[id - 1]
  end

  # The ruler of a prefecture is stored in the economic record at byte 31 as
  # hero_id + 1 (a value of 0 means there is no ruler). The ruler is the local
  # governor; the owner is the faction leader the ruler belongs to.
  def prefecture_ruler_id(pid)
    p = prefecture_by_id(pid)
    p ? p[:ruler_id] : nil
  end

  def prefecture_ruler_faction(pid)
    p = prefecture_by_id(pid)
    return nil unless p

    if p[:ruler_faction].nil? && p[:ruler_id]
      ruler = hero_by_id(p[:ruler_id])
      p[:ruler_faction] = ruler[:faction] if ruler
    end
    p[:ruler_faction]
  end

  # A hero is considered active/present in their current prefecture if they are:
  #   - the local ruler of that prefecture, OR
  #   - an unaligned person in town (faction 1, loyalty 0) with the active bit
  #     set, OR
  #   - a recruited hero (loyalty > 0) whose faction matches the ruling faction
  #     and has the active bit set.
  # Heroes present in a prefecture but not matching these conditions are
  # "invisible" or exiled.
  def hero_active_in_prefecture?(hero)
    pid = hero[:city] + 1
    return false unless prefecture_by_id(pid)

    return true if hero[:id] == prefecture_ruler_id(pid)
    return true if hero[:faction] == 1 && hero[:loyalty] == 0 && hero[:active]

    ruler_faction = prefecture_ruler_faction(pid)
    return true if ruler_faction && hero[:faction] == ruler_faction && hero[:active]

    false
  end

  def year
    @save.scenario_setup.year
  end

  def month
    @save.scenario_setup.month
  end

  def date
    @save.scenario_setup.date
  end

  def print_summary
    puts "File: #{@filename} (#{@save.raw_data.bytesize} bytes)"
    puts "Version: #{@version}"
    puts "Date: #{year}-#{month.to_s.rjust(2, "0")}"
    puts

    puts "=" * 60
    puts "Heroes (from notes)"
    puts "=" * 60

    note_hero_ids = [0, 2, 4, 5, 11, 124, 171, 145, 146, 63, 239]
    note_hero_ids.each do |id|
      h = hero_by_id(id)
      puts "\n#{h[:name]} (ID #{id})"
      puts "  Age: #{h[:age]}"
      puts "  Role: #{h[:role]}"
      puts "  Active (status byte): #{h[:active] ? "Y" : "N"}"
      puts "  Active in prefecture: #{h[:active_in_prefecture] ? "Y" : "N"}"
      puts "  Exiled: #{h[:exiled] ? "Y" : "N"}"
      puts "  Body: #{h[:body]}"
      puts "  Strength: #{h[:strength]}"
      puts "  Dexterity: #{h[:dexterity]}"
      puts "  Wisdom: #{h[:wisdom]}"
      puts "  Integrity: #{h[:integrity]}"
      puts "  Mercy: #{h[:mercy]}"
      puts "  Courage: #{h[:courage]}"
      puts "  Men: #{h[:men]}"
      puts "  Loyalty: #{h[:loyalty]}" if h[:loyalty] > 0
      puts "  Faction: #{h[:faction]}"
      puts "  City (prefecture ID - 1): #{h[:city]}"
      puts "  Raw bytes: #{h[:raw].map { |b| b.to_s(16).rjust(2, "0") }.join(" ")}"
    end

    puts
    puts "=" * 60
    puts "Prefectures (from notes)"
    puts "=" * 60

    note_prefecture_ids = [5, 21, 23, 25, 30]
    note_prefecture_ids.each do |id|
      p = prefecture_by_id(id)
      puts "\nPrefecture #{p[:id]}, #{p[:name]}"
      puts "  Gold: #{p[:gold]}"
      puts "  Food: #{p[:food]}"
      puts "  Fur: #{p[:fur]}"
      puts "  Rate: #{p[:rate]}"
      puts "  Flood: #{p[:flood]}"
      puts "  Land: #{p[:land]}"
      puts "  Wealth: #{p[:wealth]}"
      puts "  Metal: #{p[:metal]}"
      puts "  Support: #{p[:support]}"
      puts "  Arms: #{p[:arms]}"
      puts "  Skill: #{p[:skill]}"
      puts "  Raw bytes: #{p[:raw][0..15].map { |b| b.to_s(16).rjust(2, "0") }.join(" ")}"
    end
  end

  # Output a human-readable summary in the style of notes.txt
  def print_notes_style
    puts "# People"
    note_hero_ids = [0, 2, 4, 5, 11, 124, 171, 145, 146, 63, 239]
    note_hero_ids.each do |id|
      h = hero_by_id(id)
      puts "\n#{h[:name]}"
      puts "Age #{h[:age]}" if h[:age] > 0
      puts "Role: #{h[:role]}"
      puts "Active (status byte): #{h[:active] ? "Y" : "N"}"
      puts "Active in prefecture: #{h[:active_in_prefecture] ? "Y" : "N"}"
      puts "Exiled: #{h[:exiled] ? "Y" : "N"}"
      puts
      puts "Body #{h[:body]}"
      puts "Strength #{h[:strength]}"
      puts "Dexterity #{h[:dexterity]}"
      puts "Wisdom #{h[:wisdom]}"
      puts "Men #{h[:men]}"
      puts "Loyalty #{h[:loyalty]}" if h[:loyalty] > 0
      puts "Raw status byte: 0x#{h[:status_byte].to_s(16).rjust(2, "0")}"
      puts "Ship: #{h[:has_ship] ? "Y" : "N"}"
      puts
      puts "As #{h[:status].downcase}, prefecture #{h[:city] + 1}"
      puts "-----"
    end

    puts
    puts "# Prefectures"
    note_prefecture_ids = [5, 21, 23, 25, 30]
    note_prefecture_ids.each do |id|
      p = prefecture_by_id(id)
      puts "\nPrefecture #{p[:id]}, #{p[:name]}"
      puts "Gold #{p[:gold]}"
      puts "Food #{p[:food]}"
      puts "Fur #{p[:fur]}"
      puts "Rate #{p[:rate]}"
      puts "Flood #{p[:flood]}"
      puts "Land #{p[:land]}"
      puts "Wealth #{p[:wealth]}"
      puts "Metal #{p[:metal]}"
      puts "Support #{p[:support]}"
      puts "Arms #{p[:arms]}"
      puts "Skill #{p[:skill]}"
      puts "====="
    end
  end

  def print_all_prefectures
    puts "=" * 70
    puts "All Prefectures (#{@filename})"
    puts "=" * 70

    @prefectures.each do |p|
      puts "\nPrefecture #{p[:id]}: #{p[:name]}"
      puts "  @ 0x#{p[:offset].to_s(16)}"
      puts "  Gold=#{p[:gold]} Food=#{p[:food]} Metal=#{p[:metal]} Fur=#{p[:fur]}"
      puts "  Rate=#{p[:rate]} Flood=#{p[:flood]} Land=#{p[:land]} Wealth=#{p[:wealth]} Support=#{p[:support]}"
      puts "  Arms=#{p[:arms]} Skill=#{p[:skill]} Castles=#{p[:castle_count]}"
      smithy = p[:smithy] ? "Y" : "N"
      shipyard = p[:shipyard] ? "Y" : "N"
      puts "  Smithy=#{smithy} Shipyard=#{shipyard} (facility byte 0x#{p[:facility_byte].to_s(16).rjust(2, "0")})"

      faction = prefecture_ruler_faction(p[:id])
      puts "  Faction: #{faction} (#{faction_name(faction)})" if faction

      local_heroes = @heroes.select do |h|
        h[:city] + 1 == p[:id] && h[:active] && h[:active_in_prefecture] &&
          (h[:loyalty] > 0 || h[:id] == p[:ruler_id])
      end
      local_people = @heroes.select do |h|
        h[:city] + 1 == p[:id] && h[:active] && h[:active_in_prefecture] &&
          h[:faction] == 1 && h[:loyalty] == 0 && h[:id] != p[:ruler_id]
      end
      exiled_heroes = @heroes.select do |h|
        h[:city] + 1 == p[:id] && h[:active] && h[:loyalty] > 0 && !h[:active_in_prefecture]
      end
      inactive_heroes = @heroes.select { |h| h[:city] + 1 == p[:id] && !h[:active] }
      ruler = p[:ruler_id] ? hero_by_id(p[:ruler_id]) : nil
      owner_faction = prefecture_ruler_faction(p[:id])
      owner = owner_faction ? hero_by_id(owner_faction) : nil
      local_recruits = local_heroes.reject { |h| h[:id] == p[:ruler_id] }

      unless local_heroes.empty?
        names = local_heroes.map { |h| "#{h[:name]}(#{h[:id]})" }.join(", ")
        puts "  Heroes (#{local_heroes.length}): #{names}"
      end
      unless local_recruits.empty?
        names = local_recruits.map { |h| "#{h[:name]}(#{h[:id]})" }.join(", ")
        puts "  Recruits (#{local_recruits.length}): #{names}"
      end
      unless local_people.empty?
        names = local_people.map { |h| "#{h[:name]}(#{h[:id]})" }.join(", ")
        puts "  People (#{local_people.length}): #{names}"
      end
      puts "  Owner: #{owner[:name]}" if owner
      puts "  Ruler: #{ruler[:name]}" if ruler
      unless exiled_heroes.empty?
        names = exiled_heroes.map { |h| "#{h[:name]}(#{h[:id]}) - #{h[:role]}" }.join(", ")
        puts "  Exiled (#{exiled_heroes.length}): #{names}"
      end
      unless inactive_heroes.empty?
        names = inactive_heroes.map { |h| "#{h[:name]}(#{h[:id]}) - #{h[:role]}" }.join(", ")
        puts "  Inactive (#{inactive_heroes.length}): #{names}"
      end
    end
  end

  def print_all_heroes
    puts "=" * 70
    puts "All Heroes (#{@filename})"
    puts "=" * 70

    @heroes.each do |h|
      name = h[:name]
      location = h[:location] ? "P#{h[:location][:id]} #{h[:location][:name]}" : "city #{h[:city]}"
      puts "\nID #{h[:id]}: #{name}"
      puts "  Age=#{h[:age]} Body=#{h[:body]}"
      puts "  Str=#{h[:strength]} Dex=#{h[:dexterity]} Wis=#{h[:wisdom]}"
      puts "  Int=#{h[:integrity]} Mer=#{h[:mercy]} Cou=#{h[:courage]}"
      puts "  Men=#{h[:men]} Loyalty=#{(h[:loyalty] > 0) ? h[:loyalty] : "-"}"
      puts "  Location: #{location}"
      puts "  Faction: #{h[:faction]} (#{faction_name(h[:faction])})"
      puts "  Role: #{h[:role]}"
      puts "  Active (status byte): #{h[:active] ? "Y" : "N"}"
      puts "  Active in prefecture: #{h[:active_in_prefecture] ? "Y" : "N"}"
      puts "  Exiled: #{h[:exiled] ? "Y" : "N"}"
      puts "  Status byte: 0x#{h[:status_byte].to_s(16).rjust(2, "0")}"
      puts "  Ship: #{h[:has_ship] ? "Y" : "N"}"
      puts "  Can use ship: #{h[:can_use_ship] ? "Y" : "N"}"
      puts "  Can steer: #{h[:can_steer] ? "Y" : "N"}"
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby lib/bandit_kings/parser.rb [options] <save_file>"
    opts.on("-a", "--all-prefectures", "Print all prefectures") do
      options[:all_prefectures] = true
    end
    opts.on("-H", "--all-heroes", "Print all heroes") do
      options[:all_heroes] = true
    end
    opts.on("-n", "--notes-style", "Output in notes.txt style") do
      options[:notes_style] = true
    end
  end.parse!

  filename = ARGV[0]
  raise OptionParser::MissingArgument, "filename" unless filename

  parser = BanditKingsParser.new(filename)
  if options[:notes_style]
    parser.print_notes_style
  else
    parser.print_summary
  end
  parser.print_all_prefectures if options[:all_prefectures]
  parser.print_all_heroes if options[:all_heroes]
end
