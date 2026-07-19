#!/usr/bin/env ruby

# Ruby data model for a Bandit Kings of Ancient China scenario/save file
# (SUI0 / SUI1, 21122 bytes).
#
# The goal is a 1:1 relationship between every byte in the file and a named
# span. Anything currently parsed is a *known* field; everything else is an
# *unknown* field kept in the structs so we can track what is still left to
# decode.
#
# Layout verified against the original disassembly in
# bandits_dasm/bk.bin_CODE_5.txt: after the 4-byte "SUI0"/"SUI1" header, the
# game reads five sequential blocks:
#   hero records       (255 x 24 bytes) starting at 0x0004
#   scenario setup     (328 bytes)      starting at 0x17ec
#   prefecture records (49 x 32 bytes)  starting at 0x1934
#   tactical records   (49 x 28 bytes)  starting at 0x1f54
#   hero name table    (255 x 46 bytes) starting at 0x24b0
# These sum to 21118 bytes, plus the 4-byte header = 21122.
#
# The 49 prefectures are stored as one flat table; there is no "grid". The
# game map is an arbitrary graph, and the adjacency is handled elsewhere (in
# the tactical records or in the executable). The first four prefectures are
# simply the first four records in the table, not a special "pre-grid" region.

module BanditKings
  FILE_SIZE = 21_122

  HERO_COUNT = 255
  HERO_RECORD_SIZE = 24
  HERO_OFFSET = 4

  PREFECTURE_COUNT = 49
  PREFECTURE_RECORD_SIZE = 32
  PREFECTURE_RECORD_START = 0x1934

  TACTICAL_RECORD_START = 0x1f54
  TACTICAL_RECORD_SIZE = 28

  HERO_NAME_TABLE_START = 0x24b0
  HERO_NAME_TABLE_RECORD_SIZE = 46

  SCENARIO_SETUP_START = 0x17ec
  SCENARIO_SETUP_SIZE = 0x1934 - 0x17ec

  # The game engine supports exactly 11 simultaneous faction leaders. The
  # scenario-setup region contains three parallel 11-entry arrays:
  #   - leader ID table: 11 bytes at offset 0x45 from the scenario setup start
  #   - leader flags:    11 words at offset 0x50
  #   - leader D/status: 11 bytes at offset 0x7c
  MAX_LEADER_COUNT = 11

  SCENARIO_SETUP_LEADER_TABLE_OFFSET = 0x45
  SCENARIO_SETUP_LEADER_FLAGS_OFFSET = 0x50
  SCENARIO_SETUP_LEADER_FLAGS_ENTRY_SIZE = 2
  SCENARIO_SETUP_LEADER_D_OFFSET = 0x7c
  SCENARIO_SETUP_YEAR_OFFSET = 0
  SCENARIO_SETUP_MONTH_OFFSET = 2

  # Hero status byte bit masks (byte 23 of the hero record).
  #   bit 7 (0x80): active / present in the scenario
  #   bit 6 (0x40): has a ship (can move on water)
  #   bit 5 (0x20): town person (faction 1, loyalty 0)
  # The lower bits (especially bits 2-4) appear to encode the "Position"
  # profession string shown on the hero screen. They should be preserved when
  # changing a hero's role.
  STATUS_ACTIVE = 0x80
  STATUS_SHIP = 0x40
  STATUS_TOWN = 0x20
  STATUS_PROFESSION_MASK = 0x1f

  # Hero name table suffix byte bit masks (byte 0 of the 2-byte suffix).
  #   bit 7 (0x80): can use/navigate ships
  #   bit 6 (0x40): can steer a ship (lead naval movement)
  # The lower 6 bits are the appearance year (year - 1100; 0 = starting year 1101).
  SUFFIX_CAN_USE_SHIP = 0x80
  SUFFIX_CAN_STEER = 0x40
  SUFFIX_APPEARANCE_YEAR_MASK = 0x3f

  # Tactical record facility byte flags (byte 26).
  FACILITY_SHIPYARD = 0x01
  FACILITY_SMITHY = 0x02
  FACILITY_UNKNOWN = 0x04

  # ---------------------------------------------------------------------------
  # Header (4 bytes)
  # ---------------------------------------------------------------------------
  Header = Struct.new(:version, keyword_init: true) do
    def self.unpack(bytes)
      raise ArgumentError, "Header must be 4 bytes, got #{bytes.bytesize}" unless bytes.bytesize == 4

      new(version: bytes[0, 4].force_encoding("ASCII-8BIT"))
    end

    def pack
      version[0, 4].b
    end
  end

  # ---------------------------------------------------------------------------
  # Hero record (24 bytes, 255 entries, first entry at 0x4)
  #
  # Byte mapping:
  #   0-3   unknown prefix (always zero in known files)
  #   4     age
  #   5     faction: hero ID of the liege/owner; own ID = ruler; 1 = town person
  #   6     city (prefecture ID - 1)
  #   7-8   body / body2: current and maximum stamina (both start at 100)
  #   9     integrity
  #   10    mercy
  #   11    courage
  #   12    strength
  #   13    dexterity
  #   14    wisdom
  #   15-17 unknown
  #   18    loyalty: 0 = unaligned town person, >0 = recruited by faction
  #   19-21 unknown
  #   22    men (number of followers/troops under the hero)
  #   23    status byte
  # ---------------------------------------------------------------------------
  HeroRecord = Struct.new(
    :unknown_0, :unknown_1, :unknown_2, :unknown_3,
    :age, :faction, :city, :body, :body2,
    :integrity, :mercy, :courage, :strength, :dexterity, :wisdom,
    :unknown_11, :unknown_12, :unknown_14,
    :loyalty, :unknown_15, :unknown_16, :unknown_17,
    :men, :status_byte,
    keyword_init: true
  ) do
    def self.unpack(bytes)
      raise ArgumentError, "HeroRecord must be #{HERO_RECORD_SIZE} bytes" unless bytes.bytesize == HERO_RECORD_SIZE

      b = bytes.bytes
      new(
        unknown_0: b[0], unknown_1: b[1], unknown_2: b[2], unknown_3: b[3],
        age: b[4], faction: b[5], city: b[6], body: b[7], body2: b[8],
        integrity: b[9], mercy: b[10], courage: b[11],
        strength: b[12], dexterity: b[13], wisdom: b[14],
        unknown_11: b[15], unknown_12: b[16], unknown_14: b[17],
        loyalty: b[18], unknown_15: b[19], unknown_16: b[20], unknown_17: b[21],
        men: b[22], status_byte: b[23]
      )
    end

    def pack
      [
        unknown_0, unknown_1, unknown_2, unknown_3,
        age, faction, city, body, body2,
        integrity, mercy, courage, strength, dexterity, wisdom,
        unknown_11, unknown_12, unknown_14,
        loyalty, unknown_15, unknown_16, unknown_17,
        men, status_byte
      ].pack("C*")
    end

    def active?
      (status_byte & STATUS_ACTIVE) != 0
    end

    def has_ship?
      (status_byte & STATUS_SHIP) != 0
    end

    def profession_bits
      status_byte & STATUS_PROFESSION_MASK
    end
  end

  # ---------------------------------------------------------------------------
  # Scenario setup region (0x17ec-0x1933, 328 bytes)
  # ---------------------------------------------------------------------------
  ScenarioSetup = Struct.new(:raw_bytes, keyword_init: true) do
    def self.unpack(bytes)
      unless bytes.bytesize == SCENARIO_SETUP_SIZE
        raise ArgumentError, "ScenarioSetup must be #{SCENARIO_SETUP_SIZE} bytes"
      end

      new(raw_bytes: bytes.bytes)
    end

    def pack
      raw_bytes.pack("C*")
    end

    # 0x17ec-0x17ed: 16-bit big-endian year (e.g. 0x04 0x5b = 1115)
    # 0x17ee:        month, 1-12 (1 = January, ..., 12 = December)
    def year
      (raw_bytes[SCENARIO_SETUP_YEAR_OFFSET] << 8) | raw_bytes[SCENARIO_SETUP_YEAR_OFFSET + 1]
    end

    def year=(value)
      raw_bytes[SCENARIO_SETUP_YEAR_OFFSET] = (value >> 8) & 0xFF
      raw_bytes[SCENARIO_SETUP_YEAR_OFFSET + 1] = value & 0xFF
    end

    def month
      raw_bytes[SCENARIO_SETUP_MONTH_OFFSET]
    end

    def month=(value)
      raw_bytes[SCENARIO_SETUP_MONTH_OFFSET] = value
    end

    def date
      {year: year, month: month}
    end

    # 0x17ef-0x17f3: 5 remaining bytes of the 8-byte header; purpose unknown
    def header_bytes
      raw_bytes[0, 8]
    end

    # 0x17f4-0x17fa: 7 unknown bytes; the values [15, 5, 0, 0, 0, 255, 255] do
    # not correspond to actual hero positions, so this span is treated as opaque.
    def unknown_header_bytes_2
      raw_bytes[8, 7]
    end

    def unknown_header_trailer
      raw_bytes[15]
    end

    # 0x17fc-0x1825: 42-byte table of remaining prefecture IDs
    def remaining_prefecture_ids
      raw_bytes[16, 42]
    end

    # 0x1826-0x1933: the still-unknown tail of the region
    def unknown_tail
      start = 0x1826 - SCENARIO_SETUP_START
      raw_bytes[start, SCENARIO_SETUP_SIZE - start]
    end

    # 0x45-0x4f: 11-byte table of starting leader hero IDs (255/0 = empty slot)
    def leader_table
      raw_bytes[SCENARIO_SETUP_LEADER_TABLE_OFFSET, MAX_LEADER_COUNT].dup
    end

    def leader_table=(values)
      values = values.dup
      values.fill(255, values.length...MAX_LEADER_COUNT) if values.length < MAX_LEADER_COUNT
      raw_bytes[SCENARIO_SETUP_LEADER_TABLE_OFFSET, MAX_LEADER_COUNT] = values.first(MAX_LEADER_COUNT)
    end

    def first_empty_leader_slot
      leader_table.index { |b| [255, 0].include?(b) }
    end

    # 0x50-0x65: 11-word table of leader flags. The flag indicates whether the
    # leader starts the scenario already ruling their assigned prefecture:
    #   0x0001 = exiled / starting leader (not currently ruling a prefecture)
    #   0x0000 = settled ruler (the hero is the actual ruler of their prefecture)
    # This must match the hero's actual ruler status; mismatches cause crashes.
    def leader_flags
      MAX_LEADER_COUNT.times.map do |i|
        off = SCENARIO_SETUP_LEADER_FLAGS_OFFSET + i * SCENARIO_SETUP_LEADER_FLAGS_ENTRY_SIZE
        (raw_bytes[off] << 8) | raw_bytes[off + 1]
      end
    end

    def leader_flags=(values)
      MAX_LEADER_COUNT.times do |i|
        off = SCENARIO_SETUP_LEADER_FLAGS_OFFSET + i * SCENARIO_SETUP_LEADER_FLAGS_ENTRY_SIZE
        if i < values.length
          word = values[i]
          raw_bytes[off] = (word >> 8) & 0xFF
          raw_bytes[off + 1] = word & 0xFF
        else
          raw_bytes[off] = 0
          raw_bytes[off + 1] = 0
        end
      end
    end

    # 0x7c-0x86: 11-byte leader D/status table. Observed values:
    #   0x00 = exiled / starting leader
    #   0x32 = settled ruler (matches the NPCs and any settled player leader)
    def leader_d_bytes
      raw_bytes[SCENARIO_SETUP_LEADER_D_OFFSET, MAX_LEADER_COUNT].dup
    end

    def leader_d_bytes=(values)
      values = values.dup
      values.fill(0, values.length...MAX_LEADER_COUNT) if values.length < MAX_LEADER_COUNT
      raw_bytes[SCENARIO_SETUP_LEADER_D_OFFSET, MAX_LEADER_COUNT] = values.first(MAX_LEADER_COUNT)
    end
  end

  # ---------------------------------------------------------------------------
  # Prefecture economic record (32 bytes, 49 entries, 0x1934-0x1f53)
  #
  # Byte mapping:
  #   0-11  unknown
  #   12-13 gold
  #   14-15 food
  #   16-17 metal
  #   18-19 fur
  #   20    rate
  #   21    flood
  #   22    land
  #   23    wealth
  #   24    support
  #   25    arms
  #   26    skill
  #   27-30 unknown
  #   31    ruler_id_plus_one (0 => no ruler, otherwise hero_id + 1)
  # ---------------------------------------------------------------------------
  PrefectureRecord = Struct.new(
    :unknown_0, :unknown_1, :unknown_2, :unknown_3,
    :unknown_4, :unknown_5, :unknown_6, :unknown_7,
    :unknown_8, :unknown_9, :unknown_10, :unknown_11,
    :gold_hi, :gold_lo, :food_hi, :food_lo,
    :metal_hi, :metal_lo, :fur_hi, :fur_lo,
    :rate, :flood, :land, :wealth, :support, :arms, :skill,
    :unknown_27, :unknown_28, :unknown_29, :unknown_30,
    :ruler_id_plus_one,
    keyword_init: true
  ) do
    def self.unpack(bytes)
      unless bytes.bytesize == PREFECTURE_RECORD_SIZE
        raise ArgumentError, "PrefectureRecord must be #{PREFECTURE_RECORD_SIZE} bytes"
      end

      b = bytes.bytes
      new(
        unknown_0: b[0], unknown_1: b[1], unknown_2: b[2], unknown_3: b[3],
        unknown_4: b[4], unknown_5: b[5], unknown_6: b[6], unknown_7: b[7],
        unknown_8: b[8], unknown_9: b[9], unknown_10: b[10], unknown_11: b[11],
        gold_hi: b[12], gold_lo: b[13],
        food_hi: b[14], food_lo: b[15],
        metal_hi: b[16], metal_lo: b[17],
        fur_hi: b[18], fur_lo: b[19],
        rate: b[20], flood: b[21], land: b[22], wealth: b[23],
        support: b[24], arms: b[25], skill: b[26],
        unknown_27: b[27], unknown_28: b[28], unknown_29: b[29], unknown_30: b[30],
        ruler_id_plus_one: b[31]
      )
    end

    def pack
      [
        unknown_0, unknown_1, unknown_2, unknown_3,
        unknown_4, unknown_5, unknown_6, unknown_7,
        unknown_8, unknown_9, unknown_10, unknown_11,
        gold_hi, gold_lo, food_hi, food_lo, metal_hi, metal_lo, fur_hi, fur_lo,
        rate, flood, land, wealth, support, arms, skill,
        unknown_27, unknown_28, unknown_29, unknown_30,
        ruler_id_plus_one
      ].pack("C*")
    end

    def gold
      (gold_hi << 8) | gold_lo
    end

    def food
      (food_hi << 8) | food_lo
    end

    def metal
      (metal_hi << 8) | metal_lo
    end

    def fur
      (fur_hi << 8) | fur_lo
    end

    def ruler_id
      (ruler_id_plus_one > 0) ? ruler_id_plus_one - 1 : nil
    end
  end

  # ---------------------------------------------------------------------------
  # Tactical map / facility record (28 bytes, 49 entries, 0x1f54-0x24af)
  #
  # Byte mapping:
  #   0-9   null-terminated ASCII name
  #   10-11 unknown
  #   11    castle count
  #   12-25 unknown
  #   26    facility flags (shipyard/smithy/unknown)
  #   27    unknown
  # ---------------------------------------------------------------------------
  TacticalRecord = Struct.new(
    :name_field,
    :unknown_10, :castle_count,
    :unknown_12, :unknown_13, :unknown_14, :unknown_15,
    :unknown_16, :unknown_17, :unknown_18, :unknown_19,
    :unknown_20, :unknown_21, :unknown_22, :unknown_23,
    :unknown_24, :unknown_25,
    :facility_byte, :unknown_27,
    keyword_init: true
  ) do
    def self.unpack(bytes)
      unless bytes.bytesize == TACTICAL_RECORD_SIZE
        raise ArgumentError, "TacticalRecord must be #{TACTICAL_RECORD_SIZE} bytes"
      end

      b = bytes.bytes
      new(
        name_field: bytes[0, 10].b,
        unknown_10: b[10], castle_count: b[11],
        unknown_12: b[12], unknown_13: b[13], unknown_14: b[14], unknown_15: b[15],
        unknown_16: b[16], unknown_17: b[17], unknown_18: b[18], unknown_19: b[19],
        unknown_20: b[20], unknown_21: b[21], unknown_22: b[22], unknown_23: b[23],
        unknown_24: b[24], unknown_25: b[25],
        facility_byte: b[26], unknown_27: b[27]
      )
    end

    def pack
      [
        name_field[0, 10].b,
        unknown_10, castle_count,
        unknown_12, unknown_13, unknown_14, unknown_15,
        unknown_16, unknown_17, unknown_18, unknown_19,
        unknown_20, unknown_21, unknown_22, unknown_23,
        unknown_24, unknown_25,
        facility_byte, unknown_27
      ].pack("a10C18")
    end

    def name
      name_field.unpack1("Z*").force_encoding("ASCII-8BIT")
    end

    def shipyard?
      (facility_byte & FACILITY_SHIPYARD) != 0
    end

    def smithy?
      (facility_byte & FACILITY_SMITHY) != 0
    end

    def unknown_facility?
      (facility_byte & FACILITY_UNKNOWN) != 0
    end
  end

  # ---------------------------------------------------------------------------
  # Hero name table entry (46 bytes, 255 entries, 0x24b0)
  #
  # Byte mapping:
  #   0-15   16-byte name (null-terminated ASCII)
  #   16-43  28-byte nickname (null-terminated ASCII)
  #   44-45  2-byte suffix
  #     suffix[0] bits:
  #       0x80: can use/navigate ships
  #       0x40: can steer a ship (can lead naval movement)
  #       bits 0-5: appearance year (year - 1100; 0 = starting year 1101)
  # ---------------------------------------------------------------------------
  HeroNameEntry = Struct.new(
    :name_field, :nickname_field, :suffix,
    keyword_init: true
  ) do
    def self.unpack(bytes)
      unless bytes.bytesize == HERO_NAME_TABLE_RECORD_SIZE
        raise ArgumentError, "HeroNameEntry must be #{HERO_NAME_TABLE_RECORD_SIZE} bytes"
      end

      new(
        name_field: bytes[0, 16].b,
        nickname_field: bytes[16, 28].b,
        suffix: bytes[44, 2].b
      )
    end

    def pack
      name_field[0, 16].b + nickname_field[0, 28].b + suffix[0, 2].b
    end

    def name
      name_field.unpack1("Z*").force_encoding("ASCII-8BIT")
    end

    def nickname
      nickname_field.unpack1("Z*").force_encoding("ASCII-8BIT")
    end

    def suffix_byte
      suffix[0].ord
    end

    def can_use_ship?
      (suffix_byte & SUFFIX_CAN_USE_SHIP) != 0
    end

    def can_steer?
      (suffix_byte & SUFFIX_CAN_STEER) != 0
    end

    def appearance_year
      suffix_byte & SUFFIX_APPEARANCE_YEAR_MASK
    end
  end

  # ---------------------------------------------------------------------------
  # Generic catch-all for a span of bytes whose meaning is not yet known.
  # ---------------------------------------------------------------------------
  UnknownSpan = Struct.new(:offset, :raw_bytes, keyword_init: true) do
    def size
      raw_bytes.size
    end

    def bytes
      raw_bytes
    end
  end

  # ---------------------------------------------------------------------------
  # Full file representation
  # ---------------------------------------------------------------------------
  SaveFile = Struct.new(
    :header, :heroes, :scenario_setup, :prefecture_records,
    :tactical_records, :hero_name_entries, :unknown_regions, :raw_data,
    keyword_init: true
  ) do
    def self.read(path)
      data = File.binread(path)
      raise ArgumentError, "Expected #{FILE_SIZE} bytes, got #{data.bytesize}" unless data.bytesize == FILE_SIZE

      header = Header.unpack(data[0, 4])
      heroes = Array.new(HERO_COUNT) do |id|
        off = HERO_OFFSET + id * HERO_RECORD_SIZE
        HeroRecord.unpack(data[off, HERO_RECORD_SIZE])
      end

      scenario_setup = ScenarioSetup.unpack(data[SCENARIO_SETUP_START, SCENARIO_SETUP_SIZE])

      prefecture_records = PREFECTURE_COUNT.times.map do |i|
        off = PREFECTURE_RECORD_START + i * PREFECTURE_RECORD_SIZE
        PrefectureRecord.unpack(data[off, PREFECTURE_RECORD_SIZE])
      end

      tactical_records = PREFECTURE_COUNT.times.map do |i|
        off = TACTICAL_RECORD_START + i * TACTICAL_RECORD_SIZE
        TacticalRecord.unpack(data[off, TACTICAL_RECORD_SIZE])
      end

      hero_name_entries = HERO_COUNT.times.map do |id|
        off = HERO_NAME_TABLE_START + id * HERO_NAME_TABLE_RECORD_SIZE
        HeroNameEntry.unpack(data[off, HERO_NAME_TABLE_RECORD_SIZE])
      end

      unknown_regions = []
      # 0x1826-0x1933: the still-unknown tail of the scenario setup region.
      unknown_regions << UnknownSpan.new(
        offset: 0x1826,
        raw_bytes: data[0x1826, 0x1933 - 0x1826 + 1].bytes
      )

      new(
        header: header, heroes: heroes, scenario_setup: scenario_setup,
        prefecture_records: prefecture_records, tactical_records: tactical_records,
        hero_name_entries: hero_name_entries, unknown_regions: unknown_regions,
        raw_data: data
      )
    end

    def version
      header.version
    end

    # Reconstruct the known spans. Because the blocks are contiguous and
    # non-overlapping, this should round-trip cleanly for the portions covered
    # by the structs. Unknown regions are *not* included; mutating those still
    # requires using raw_data as the ground truth.
    def repack
      buf = String.new(encoding: "ASCII-8BIT")
      buf << header.pack
      heroes.each { |h| buf << h.pack }
      buf << scenario_setup.pack
      PREFECTURE_COUNT.times do |i|
        buf << prefecture_records[i].pack
      end
      tactical_records.each { |r| buf << r.pack }
      hero_name_entries.each { |e| buf << e.pack }
      buf
    end

    def memory_map_spans
      [
        {start: 0x0000, finish: 0x0003, label: "Header (version, 4 bytes)"},
        {start: 0x0004, finish: 0x17eb, label: "Hero records (255 x 24 bytes)"},
        {start: 0x17ec, finish: 0x1933, label: "Scenario setup (328 bytes, partially known)"},
        {start: 0x1934, finish: 0x1f53, label: "Prefecture records (49 x 32 bytes)"},
        {start: 0x1f54, finish: 0x24af, label: "Tactical map / facility records (49 x 28 bytes)"},
        {start: 0x24b0, finish: 0x5281, label: "Hero name table (255 x 46 bytes)"}
      ]
    end

    def overlap_regions
      spans = memory_map_spans
      overlaps = []
      spans.each_with_index do |a, i|
        spans[(i + 1)..].each do |b|
          next if a[:finish] < b[:start] || b[:finish] < a[:start]

          overlap_start = [a[:start], b[:start]].max
          overlap_finish = [a[:finish], b[:finish]].min
          overlaps << {
            start: overlap_start,
            finish: overlap_finish,
            labels: [a[:label], b[:label]]
          }
        end
      end
      overlaps
    end

    def print_memory_map
      puts "Memory map for Bandit Kings save/scenario file (#{FILE_SIZE} bytes)"
      puts "=" * 80
      puts format("%-10s  %-10s  %-8s  %s", "Start", "End", "Size", "Description")
      puts "-" * 80

      memory_map_spans.each do |span|
        size = span[:finish] - span[:start] + 1
        puts format("0x%-8x  0x%-8x  %-8d  %s", span[:start], span[:finish], size, span[:label])
      end

      overlaps = overlap_regions
      unless overlaps.empty?
        puts
        puts "WARNING: the following bytes are claimed by more than one structure"
        puts "-" * 80
        overlaps.each do |ov|
          size = ov[:finish] - ov[:start] + 1
          puts format("0x%-8x  0x%-8x  %-8d  %s", ov[:start], ov[:finish], size, ov[:labels].join(" <-> "))
        end
      end

      puts
      puts "Unknown regions tracked separately:"
      puts "-" * 80
      unknown_regions.each do |u|
        puts format("0x%-8x  0x%-8x  %-8d  unknown bytes", u.offset, u.offset + u.size - 1, u.size)
      end
    end

    def verify_total_coverage
      accounted = Array.new(FILE_SIZE, false)
      memory_map_spans.each do |span|
        (span[:start]..span[:finish]).each { |o| accounted[o] = true }
      end
      unknown_regions.each { |u| (u.offset...u.offset + u.size).each { |o| accounted[o] = true } }
      missing = accounted.each_index.reject { |i| accounted[i] }
      puts "Missing bytes: #{missing.length}"
      missing.each { |o| puts "  0x#{o.to_s(16)}" } unless missing.empty?
      missing.empty?
    end
  end
end

if __FILE__ == $0
  file = ARGV[0] || "/home/dan/sandbox/bandit_kings_modding/scen_1_shi_lin_wu"
  save = BanditKings::SaveFile.read(file)
  save.print_memory_map

  puts
  puts "Coverage check:"
  save.verify_total_coverage

  puts
  puts "Sample hero 0: #{save.heroes[0].inspect}"
  puts "Sample prefecture 1 (#{save.tactical_records[0].name}): #{save.prefecture_records[0].inspect}"
  puts "Sample tactical 1 (#{save.tactical_records[0].name}): #{save.tactical_records[0].inspect}"
  puts "Sample name entry 0: #{save.hero_name_entries[0].inspect}"
end
