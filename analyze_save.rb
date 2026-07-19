#!/usr/bin/env ruby
# Analyze Bandit Kings of Ancient China save/scenario files.
#
# By default, prints a human-readable summary of all prefectures and heroes.
# With -c, writes CSV summaries instead.
#
# Usage:
#   ruby analyze_save.rb [options] [file1 file2 ...]
#
# If no files are given, all *.CIM and scen_* files in the current directory
# are processed.

require "csv"
require "optparse"
require_relative "lib/bandit_kings"

options = {csv: false}
OptionParser.new do |opts|
  opts.banner = "Usage: ruby analyze_save.rb [options] [file1 file2 ...]"
  opts.on("-c", "--csv", "Write CSV summaries for each file") do
    options[:csv] = true
  end
  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end.parse!

files = if ARGV.empty?
  Dir["*.CIM"] + Dir["scen_*"]
else
  ARGV
end

files = files.select { |f| File.file?(f) }.sort

if files.empty?
  warn "No save/scenario files found."
  exit 1
end

def generate_prefecture_csv(parser, filename)
  CSV.open(filename, "w") do |csv|
    csv << %w[
      ID Name Faction FactionName Gold Food Metal Fur Rate Flood Land Wealth
      Support Arms Skill Castles Smithy Shipyard HeroesCount RecruitsCount
      PeopleCount Ruler Owner
    ]
    parser.prefectures.each do |p|
      heroes = parser.heroes.select do |h|
        h[:city] + 1 == p[:id] && h[:active] && h[:active_in_prefecture] &&
          (h[:loyalty] > 0 || h[:id] == p[:ruler_id])
      end
      people = parser.heroes.select do |h|
        h[:city] + 1 == p[:id] && h[:active] && h[:active_in_prefecture] &&
          h[:faction] == 1 && h[:loyalty] == 0 && h[:id] != p[:ruler_id]
      end
      ruler = p[:ruler_id] ? parser.hero_by_id(p[:ruler_id])[:name] : ""
      owner_id = p[:ruler_id] ? parser.prefecture_ruler_faction(p[:id]) : nil
      owner = owner_id ? parser.hero_by_id(owner_id)[:name] : ""
      faction = owner_id
      faction_name = owner_id ? parser.faction_name(owner_id) : ""
      recruits_count = heroes.length - (p[:ruler_id] ? 1 : 0)
      csv << [
        p[:id], p[:name], faction, faction_name, p[:gold], p[:food], p[:metal],
        p[:fur], p[:rate], p[:flood], p[:land], p[:wealth], p[:support], p[:arms],
        p[:skill], p[:castle_count], p[:smithy] ? "Y" : "N",
        p[:shipyard] ? "Y" : "N", heroes.length, recruits_count, people.length,
        ruler, owner
      ]
    end
  end
end

def generate_hero_csv(parser, filename)
  CSV.open(filename, "w") do |csv|
    csv << %w[
      ID Name Faction FactionName Age Body Strength Dexterity Wisdom Integrity
      Mercury Courage Men Loyalty Location Role Active State CanSteer CanUseShip
      HasShip
    ]
    parser.heroes.each do |h|
      location = h[:location] ? "P#{h[:location][:id]} #{h[:location][:name]}" : "city #{h[:city]}"
      state = if h[:exiled]
        "Exiled"
      elsif !h[:active]
        "Inactive"
      elsif h[:role] == "Person in town"
        "In Town"
      elsif h[:role] == "Owner/Ruler"
        "Owner/Ruler"
      else
        "Recruit"
      end
      csv << [
        h[:id], h[:name], h[:faction], parser.faction_name(h[:faction]), h[:age],
        h[:body], h[:strength], h[:dexterity], h[:wisdom],
        h[:integrity], h[:mercy], h[:courage], h[:men], (h[:loyalty] > 0) ? h[:loyalty] : "",
        location, h[:role], h[:active] ? "Y" : "N", state,
        h[:can_steer] ? "Y" : "N", h[:can_use_ship] ? "Y" : "N", h[:has_ship] ? "Y" : "N"
      ]
    end
  end
end

def generate_csvs(parser, file)
  cleaned = file.tr(".", "_")
  generate_prefecture_csv(parser, "#{cleaned}_prefectures.csv")
  generate_hero_csv(parser, "#{cleaned}_heroes.csv")
  puts "Generated #{cleaned}_prefectures.csv and #{cleaned}_heroes.csv from #{file}"
end

files.each do |file|
  parser = BanditKingsParser.new(file)
  if options[:csv]
    generate_csvs(parser, file)
  else
    version = File.binread(file, 4)
    puts
    puts "=" * 78
    puts "FILE: #{file} (#{version})"
    puts "DATE: #{parser.year}-#{parser.month.to_s.rjust(2, "0")}"
    puts "=" * 78
    parser.print_all_prefectures
    parser.print_all_heroes
  end
end
