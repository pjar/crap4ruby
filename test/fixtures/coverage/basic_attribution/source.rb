class BasicAttribution
  def multi(a)
    if a > 0
      "pos"
    else
      "neg"
    end
  end

  def admin?(u) = u == :admin ? true : audit!

  def name = @name

  def untouched = @never

  def empty_called; end

  def empty_never; end

  def audit!
    "audited"
  end
end
