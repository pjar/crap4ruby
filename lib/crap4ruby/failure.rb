module Crap4Ruby
  # Any pipeline failure with a defined exit code (spec §3). Raised from
  # anywhere, rescued once in CLI.run — gate exceeded (2) and success (0)
  # are normal returns, never exceptions.
  class Failure < StandardError
    attr_reader :exit_code

    def initialize(message, exit_code)
      super(message)
      @exit_code = exit_code
    end
  end
end
