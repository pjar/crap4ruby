class Conditionals
  # cc: 3 id: Conditionals#grade
  def grade(score)
    if score > 90
      :a
    elsif score > 80
      :b
    else
      :c
    end
  end

  # cc: 2 id: Conditionals#early_return
  def early_return(x)
    return :neg if x.negative?
    :ok
  end

  # cc: 2 id: Conditionals#unless_else
  def unless_else(x)
    unless x
      :none
    else
      :some
    end
  end

  # cc: 2 id: Conditionals#ternary
  def ternary(x) = x ? 1 : 0

  # cc: 3 id: Conditionals#nested
  def nested(a, b)
    if a
      if b
        :both
      end
    end
  end

  # cc: 3 id: Conditionals#mixed_modifiers
  def mixed_modifiers(x)
    x += 1 if x.even?
    x -= 1 unless x.zero?
    x
  end
end
