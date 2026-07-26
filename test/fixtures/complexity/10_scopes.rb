module Outer
  class Widget
    # cc: 2 id: Outer::Widget#render
    def render(mode)
      # cc: 2 id: Outer::Widget#helper
      def helper
        1 if rand > 0.5
      end
      mode ? helper : nil
    end

    # cc: 1 id: Outer::Widget.registry
    def self.registry
      @registry
    end

    # cc: 2 id: Outer::Widget.install
    def self.install(flag)
      # cc: 1 id: Outer::Widget#define_method@20
      define_method(flag ? :on : :off) do
        :installed
      end
    end
  end

  # cc: 1 id: Widget.reset
  def Widget.reset
    @registry = nil
  end

  FACTORY = Class.new do
    # cc: 2 id: Outer::(anon@31)#speak
    def speak(loud)
      loud ? "HI" : "hi"
    end
  end

  helper_obj = Object.new
  # cc: 1 id: Outer::(singleton@40).ping
  def helper_obj.ping
    :pong
  end

  # no-row
  Widget.class_eval "def dynamic_eval; :skipped; end"

  SHAPE = ::Data.define(:w) do
    # cc: 1 id: Outer::(anon@47)#area
    def area
      :w
    end
  end

  # A qualified constructor path names a different constant — the block
  # stays transparent, so the def uses the nearest named scope.
  Qualified::Struct.new do
    # cc: 1 id: Outer#plain
    def plain
      :p
    end
  end
end
