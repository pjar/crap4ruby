def toplevel_helper
end

module Outer
  class Widget
  end

  def Widget.reset = :r
end
