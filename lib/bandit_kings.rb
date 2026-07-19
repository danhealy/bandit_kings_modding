#!/usr/bin/env ruby

# Bandit Kings of Ancient China scenario/save editing toolkit.
#
# This is the main entry point for the high-level editing API. It loads the
# binary data model (structs), the low-level parser/inspector, and the
# high-level ScenarioEditor and ScenarioScript base class.
#
# Typical usage in a custom scenario script:
#
#   require_relative "lib/bandit_kings"
#
#   class MyScenario < BanditKings::ScenarioScript
#     def apply(editor)
#       editor.activate_all_heroes
#       editor.set_ruler(21, 41)   # make hero 21 ruler of P41
#     end
#   end
#
#   MyScenario.run if __FILE__ == $PROGRAM_NAME

require_relative "bandit_kings/structs"
require_relative "bandit_kings/parser"
require_relative "bandit_kings/scenario_editor"
require_relative "bandit_kings/scenario_script"
