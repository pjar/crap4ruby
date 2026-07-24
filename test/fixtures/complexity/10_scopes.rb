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
  end

  FACTORY = Class.new do
    # cc: 2 id: Outer::(anon@18)#speak
    def speak(loud)
      loud ? "HI" : "hi"
    end
  end

  # no-row
  Widget.class_eval "def dynamic_eval; :skipped; end"
end
