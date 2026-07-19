#!/usr/bin/env ruby

# Base class for Bandit Kings scenario-editing CLI scripts.
#
# Subclasses implement #apply(editor) and optionally override #defaults to set
# the default input/output paths. The base class handles argument parsing,
# loading the input file, running the edit, validating the output size, and
# writing it back to disk.
#
# Example:
#
#   class MyScenario < BanditKings::ScenarioScript
#     def defaults
#       { input: "SUIDATA2.CIM", output: "SUIDATA2_MINE.CIM" }
#     end
#
#     def apply(editor)
#       editor.activate_all_heroes
#     end
#   end
#
#   MyScenario.run if __FILE__ == $PROGRAM_NAME

require "optparse"

module BanditKings
  class ScenarioScript
    attr_reader :input, :output

    # Run the script. Pass ARGV or a custom argv array and optional default
    # overrides.
    def self.run(argv = ARGV, defaults = {})
      new(argv, defaults).run
    end

    def initialize(argv, default_overrides = {})
      @defaults = defaults.merge(default_overrides)
      parse_options(argv)
    end

    def run
      editor = ScenarioEditor.new(@input)
      apply(editor)
      editor.save!(@output)
      print_verification(editor)
    end

    # Subclasses override this to perform edits.
    def apply(_editor)
      raise NotImplementedError, "#{self.class} must implement #apply"
    end

    # Default input/output paths for the script.
    def defaults
      {input: "SUIDATA2.CIM", output: "SUIDATA2_OUT.CIM"}
    end

    # Optional verification hook. Subclasses can override to print custom info.
    def print_verification(editor)
      editor.print_summary
    end

    private

    def parse_options(argv)
      @input = @defaults[:input]
      @output = @defaults[:output]

      OptionParser.new do |opts|
        opts.banner = "Usage: ruby #{script_name} [options]"
        opts.separator ""
        opts.separator "Options:"
        opts.on("-i", "--input FILE", "Input CIM file (default: #{@input})") { |v| @input = v }
        opts.on("-o", "--output FILE", "Output CIM file (default: #{@output})") { |v| @output = v }
        opts.on("-h", "--help", "Print this help") do
          puts opts
          exit
        end
      end.parse!(argv)
    end

    def script_name
      File.basename($PROGRAM_NAME)
    end
  end
end
