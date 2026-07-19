#!/usr/bin/env ruby
# frozen_string_literal: true

# Read or change the in-game date of a Bandit Kings of Ancient China save file.
#
#   ruby examples/set_date.rb <input> [output] [year] [month]
#
# If only <input> is given, the current date is printed.
# If <output>, <year>, and <month> are given, a new save file is written with
# the requested date and the new date is printed.
#
# Example:
#   ruby examples/set_date.rb sept1122/sept1122 /tmp/sept1122_august.CIM 1122 8

require_relative "../lib/bandit_kings"

input = ARGV[0]
output = ARGV[1]
year = ARGV[2]&.to_i
month = ARGV[3]&.to_i

unless input
  puts "Usage: ruby examples/set_date.rb <input> [output] [year] [month]"
  exit 1
end

editor = BanditKings::ScenarioEditor.new(input)

if output && year && month
  editor.set_date(year, month)
  editor.save!(output)
end

puts "Date: #{editor.year}-#{editor.month.to_s.rjust(2, "0")}"
