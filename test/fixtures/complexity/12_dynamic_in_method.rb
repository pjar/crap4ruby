class DynamicInMethod
  # cc: 2 id: DynamicInMethod#installer
  def installer(flag)
    # cc: 2 id: DynamicInMethod#define_method@5
    define_method(flag ? :on : :off, ->(x) { x ? :yes : :no })
  end

  # cc: 2 id: DynamicInMethod#block_form
  def block_form(items)
    items.each { |i| i }
    # cc: 2 id: DynamicInMethod#sum
    define_method(:sum) do |acc|
      acc ? items.sum : 0
    end
  end
end
