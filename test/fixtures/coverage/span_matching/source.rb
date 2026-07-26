class SpanCase
  MAKER = Class.new do
    def from_anon = :a
  end

  helper = Object.new
  class << helper
    def from_singleton = :s
  end
  HELPER = helper

  %i[one two].each do |n|
    define_method("dyn_#{n}") { :d }
  end

  # simplecov:disable
  def zero_unit_ignored = :z
  # simplecov:enable

  # simplecov:disable
  if ENV["CRAP4RUBY_NEVER"]
    def ghost
      :g1
      :g2
    end
  end
  # simplecov:enable
end
