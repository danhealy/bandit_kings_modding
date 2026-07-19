#!/usr/bin/env ruby

# High-level scenario editor for Bandit Kings of Ancient China.
#
# This class hides the binary layout and the low-level struct fields behind a
# simple, scenario-authoring API. It is intentionally read-modify-write: call
# methods to mutate the scenario, then call #save to write the result.
#
# All hero/prefecture IDs passed to public methods are 1-based (matching the
# in-game prefecture numbering and the hero ID table). Internally the editor
# converts to 0-based array indices where needed.

module BanditKings
  class ScenarioEditor
    attr_reader :save_file, :input_path

    # -------------------------------------------------------------------------
    # Initialization and I/O
    # -------------------------------------------------------------------------

    def initialize(path)
      @input_path = path
      @save_file = SaveFile.read(path)
    end

    def save(path)
      data = @save_file.repack
      unless data.bytesize == FILE_SIZE
        raise "#{path}: expected #{FILE_SIZE} bytes, got #{data.bytesize}"
      end

      File.binwrite(path, data)
    end

    def save!(path)
      save(path)
      puts "Wrote #{path}"
    end

    # -------------------------------------------------------------------------
    # Low-level accessors (still useful for advanced scripts)
    # -------------------------------------------------------------------------

    def hero(id)
      @save_file.heroes[id]
    end

    def hero_name(id)
      @save_file.hero_name_entries[id].name
    end

    def prefecture(id)
      @save_file.prefecture_records[id - 1]
    end

    def tactical(id)
      @save_file.tactical_records[id - 1]
    end

    # -------------------------------------------------------------------------
    # Date helpers
    # -------------------------------------------------------------------------

    def year
      @save_file.scenario_setup.year
    end

    def month
      @save_file.scenario_setup.month
    end

    def date
      @save_file.scenario_setup.date
    end

    def set_date(year, month)
      @save_file.scenario_setup.year = year
      @save_file.scenario_setup.month = month
    end

    # -------------------------------------------------------------------------
    # Hero state helpers
    # -------------------------------------------------------------------------

    def active?(id)
      hero(id).active?
    end

    def ruler?(id)
      hero(id).faction == id
    end

    def recruit?(id)
      hero(id).loyalty > 0
    end

    def town_person?(id)
      hero(id).faction == 1 && hero(id).loyalty == 0
    end

    def hero_prefecture(id)
      hero(id).city + 1
    end

    # -------------------------------------------------------------------------
    # Hero transformations
    # -------------------------------------------------------------------------

    def activate_hero(id, body: 100)
      h = hero(id)
      h.status_byte |= STATUS_ACTIVE
      h.body = body
      h.body2 = body
    end

    def activate_all_heroes(body: 100)
      HERO_COUNT.times { |id| activate_hero(id, body: body) }
    end

    # Make a hero a ruler. Optionally install them as the ruler of a prefecture.
    def make_ruler(hero_id, prefecture_id: nil)
      h = hero(hero_id)
      h.faction = hero_id
      h.loyalty = 0
      activate_hero(hero_id)
      h.status_byte = build_status(STATUS_ACTIVE, town: false, role: 0x03, original: h.status_byte)
      install_ruler(hero_id, prefecture_id) if prefecture_id
    end

    # Recruit a hero under a faction leader.
    def make_recruit(hero_id, leader_id, loyalty: 100)
      h = hero(hero_id)
      h.faction = leader_id
      h.loyalty = loyalty
      activate_hero(hero_id)
      h.status_byte = build_status(STATUS_ACTIVE, town: false, role: 0x02, original: h.status_byte)
    end

    # Turn a hero into an unaligned person in town. Optionally place them in a
    # prefecture (but does not make them the ruler).
    def make_town_person(hero_id, prefecture_id: nil)
      h = hero(hero_id)
      h.faction = 1
      h.loyalty = 0
      activate_hero(hero_id)
      h.status_byte = build_status(STATUS_ACTIVE, town: true, role: nil, original: h.status_byte)
      move_hero(hero_id, prefecture_id) if prefecture_id
    end

    # Move a hero to a prefecture without changing their faction or role.
    def move_hero(hero_id, prefecture_id)
      hero(hero_id).city = prefecture_id - 1
    end

    # Set all attributes/persona for a hero in one call.
    def set_hero_stats(hero_id, stats = {})
      h = hero(hero_id)
      h.body = stats[:body] if stats.key?(:body)
      h.body2 = stats[:body2] if stats.key?(:body2)
      h.integrity = stats[:integrity] if stats.key?(:integrity)
      h.mercy = stats[:mercy] if stats.key?(:mercy)
      h.courage = stats[:courage] if stats.key?(:courage)
      h.strength = stats[:strength] if stats.key?(:strength)
      h.dexterity = stats[:dexterity] if stats.key?(:dexterity)
      h.wisdom = stats[:wisdom] if stats.key?(:wisdom)
    end

    # Set a hero's three attributes to a specific style, preserving the original
    # ordering of highest -> middle -> lowest.
    def set_hero_attribute_style(hero_id, high:, middle:, low:)
      h = hero(hero_id)
      attrs = { strength: h.strength, dexterity: h.dexterity, wisdom: h.wisdom }
      ordered = attrs.sort_by { |_, v| -v }.map(&:first)
      h.send(:"#{ordered[0]}=", high)
      h.send(:"#{ordered[1]}=", middle)
      h.send(:"#{ordered[2]}=", low)
    end

    # Set a hero's three persona values, preserving the original ordering of
    # highest -> middle -> lowest.
    def set_hero_persona_style(hero_id, high:, middle:, low:)
      h = hero(hero_id)
      attrs = { integrity: h.integrity, mercy: h.mercy, courage: h.courage }
      ordered = attrs.sort_by { |_, v| -v }.map(&:first)
      h.send(:"#{ordered[0]}=", high)
      h.send(:"#{ordered[1]}=", middle)
      h.send(:"#{ordered[2]}=", low)
    end

    # Convenience: set all attributes and persona to 100.
    def max_hero_stats(hero_id)
      set_hero_stats(
        hero_id,
        body: 100,
        strength: 100, dexterity: 100, wisdom: 100,
        integrity: 100, mercy: 100, courage: 100
      )
    end

    # Release all followers of a leader, making them unaligned town persons.
    def release_followers(leader_id)
      HERO_COUNT.times do |id|
        next if id == leader_id

        h = hero(id)
        next unless h.faction == leader_id && h.loyalty > 0

        make_town_person(id)
      end
    end

    # Move a leader and all their recruited followers to a prefecture, then
    # install the leader as the ruler of that prefecture. The old prefecture
    # is left without a ruler if the leader was its previous ruler.
    def move_leader_to_prefecture(leader_id, prefecture_id)
      old_prefecture = hero_prefecture(leader_id)
      clear_ruler(old_prefecture) if prefecture(old_prefecture).ruler_id == leader_id
      move_leader_and_followers(leader_id, prefecture_id)
      install_ruler(leader_id, prefecture_id)
    end

    # Move a leader and all their recruited followers to a prefecture.
    def move_leader_and_followers(leader_id, prefecture_id)
      move_hero(leader_id, prefecture_id)
      HERO_COUNT.times do |id|
        next if id == leader_id

        h = hero(id)
        move_hero(id, prefecture_id) if h.faction == leader_id && h.loyalty > 0
      end
    end

    # Return a list of every hero ID that currently rules a prefecture.
    def prefecture_ruler_ids
      ids = (1..PREFECTURE_COUNT).filter_map do |pid|
        prefecture(pid).ruler_id
      end
      ids.uniq
    end

    # Replace one leader with another: demote the old leader (and their
    # followers) to town persons, then make the new hero a ruler of the same
    # prefecture.
    def replace_leader(old_id, new_id)
      old_prefecture = hero_prefecture(old_id)
      release_followers(old_id)
      make_town_person(old_id, prefecture_id: old_prefecture)
      clear_ruler(old_prefecture) if prefecture(old_prefecture).ruler_id == old_id
      make_ruler(new_id, prefecture_id: old_prefecture)
    end

    # -------------------------------------------------------------------------
    # Ranking / selection helpers
    # -------------------------------------------------------------------------

    # Return the top N hero IDs by total attribute score, excluding any IDs in
    # the :exclude array.
    def top_heroes_by_attributes(count, exclude: [])
      candidates = (0...HERO_COUNT).reject { |id| exclude.include?(id) }
      candidates
        .sort_by { |id| [-hero(id).strength - hero(id).dexterity - hero(id).wisdom, id] }
        .first(count)
    end

    # Shuffle a list of hero IDs and divide them evenly among the given leader
    # IDs. Each hero is made a town person in their assigned leader's prefecture.
    # Returns a hash: leader_id -> [hero_id, ...].
    def distribute_heroes(hero_ids, leader_ids, rng: Random.new(42))
      shuffled = hero_ids.shuffle(random: rng)
      assignment = Hash.new { |h, k| h[k] = [] }
      shuffled.each_with_index do |hero_id, i|
        leader_id = leader_ids[i % leader_ids.length]
        assignment[leader_id] << hero_id
        make_town_person(hero_id, prefecture_id: hero_prefecture(leader_id))
      end
      assignment
    end

    # -------------------------------------------------------------------------
    # Prefecture transformations
    # -------------------------------------------------------------------------

    # Install a hero as the ruler of a prefecture and move the hero there.
    def install_ruler(hero_id, prefecture_id)
      pref = prefecture(prefecture_id)
      pref.ruler_id_plus_one = hero_id + 1
      move_hero(hero_id, prefecture_id)
    end

    # Clear the ruler of a prefecture.
    def clear_ruler(prefecture_id)
      prefecture(prefecture_id).ruler_id_plus_one = 0
    end

    # Reset a prefecture to neutral defaults (no resources, no ruler, default land/flood/wealth).
    def reset_prefecture(prefecture_id, resources = {})
      pref = prefecture(prefecture_id)
      set_prefecture_resources(
        prefecture_id,
        gold: 0, food: 0, metal: 0, fur: 0,
        flood: 50, land: 10, wealth: 10, support: 0,
        arms: 0, skill: 0, **resources
      )
      pref.ruler_id_plus_one = 0
    end

    # Set prefecture resources. Values are plain integers; the editor splits
    # 16-bit gold/food/metal/fur into high/low bytes automatically.
    def set_prefecture_resources(
      prefecture_id,
      gold: nil, food: nil, metal: nil, fur: nil,
      rate: nil, flood: nil, land: nil, wealth: nil,
      support: nil, arms: nil, skill: nil
    )
      pref = prefecture(prefecture_id)
      set_word(pref, :gold_hi, :gold_lo, gold) if gold
      set_word(pref, :food_hi, :food_lo, food) if food
      set_word(pref, :metal_hi, :metal_lo, metal) if metal
      set_word(pref, :fur_hi, :fur_lo, fur) if fur
      pref.rate = rate if rate
      pref.flood = flood if flood
      pref.land = land if land
      pref.wealth = wealth if wealth
      pref.support = support if support
      pref.arms = arms if arms
      pref.skill = skill if skill
    end

    # Add facilities to a prefecture. Pass symbols :shipyard and/or :smithy.
    def add_facility(prefecture_id, facility)
      t = tactical(prefecture_id)
      case facility
      when :shipyard
        t.facility_byte |= FACILITY_SHIPYARD
      when :smithy
        t.facility_byte |= FACILITY_SMITHY
      else
        raise ArgumentError, "Unknown facility: #{facility.inspect}"
      end
    end

    # Add smithy + shipyard to every prefecture.
    def add_all_facilities
      PREFECTURE_COUNT.times { |id| add_facility(id + 1, :shipyard); add_facility(id + 1, :smithy) }
    end

    # -------------------------------------------------------------------------
    # Leader table management
    # -------------------------------------------------------------------------

    # Set the leader table and compute matching flags/D bytes automatically.
    # Any empty slots should be passed as 255.
    def set_leader_table(leader_ids)
      @save_file.scenario_setup.leader_table = leader_ids
      @save_file.scenario_setup.leader_flags = leader_ids.map { |id| leader_flag_for(id) }
      @save_file.scenario_setup.leader_d_bytes = leader_ids.map { |id| leader_d_for(id) }
    end

    # -------------------------------------------------------------------------
    # Summary / inspection
    # -------------------------------------------------------------------------

    def summary
      {
        total_heroes: HERO_COUNT,
        active_heroes: (0...HERO_COUNT).count { |id| active?(id) },
        rulers: (0...HERO_COUNT).count { |id| ruler?(id) },
        recruits: (0...HERO_COUNT).count { |id| recruit?(id) },
        town_people: (0...HERO_COUNT).count { |id| town_person?(id) }
      }
    end

    def print_summary
      s = summary
      puts "\nScenario summary:"
      puts "  date: #{year}-#{month.to_s.rjust(2, "0")}"
      s.each { |k, v| puts "  #{k}: #{v}" }
    end

    private

    # Build a status byte from the active flag, optional town-person flag, role
    # nibble (0x02 for recruit, 0x03 for ruler), and the original profession/ship bits.
    def build_status(active, town:, role:, original:)
      status = active
      status |= STATUS_TOWN if town
      status |= (original & STATUS_SHIP)
      if role
        status |= role
        status |= (original & STATUS_PROFESSION_MASK & 0x1C)
      else
        status |= (original & STATUS_PROFESSION_MASK)
      end
      status
    end

    def set_word(record, hi_field, lo_field, value)
      record.send(:"#{hi_field}=", (value >> 8) & 0xFF)
      record.send(:"#{lo_field}=", value & 0xFF)
    end

    def leader_flag_for(hero_id)
      return 0x0000 if hero_id == 255
      settled?(hero_id) ? 0x0000 : 0x0001
    end

    def leader_d_for(hero_id)
      return 0x00 if hero_id == 255
      settled?(hero_id) ? 0x32 : 0x00
    end

    def settled?(hero_id)
      return false if hero_id == 255

      pref = prefecture(hero_prefecture(hero_id))
      pref.ruler_id_plus_one == hero_id + 1
    end
  end
end
