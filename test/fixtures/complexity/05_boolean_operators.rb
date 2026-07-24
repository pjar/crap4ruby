class Booleans
  # cc: 3 id: Booleans#both?
  def both?(a, b)
    a && b || a.nil?
  end

  # cc: 3 id: Booleans#wordy
  def wordy(a, b)
    a and b or raise
  end

  # cc: 4 id: Booleans#chain
  def chain(a, b, c, d)
    a && b && c && d
  end

  # cc: 2 id: Booleans#memo
  def memo
    @memo ||= compute
  end

  # cc: 3 id: Booleans#tighten
  def tighten(h)
    h[:k] &&= h[:k].strip
    @flag ||= true
    h
  end
end
