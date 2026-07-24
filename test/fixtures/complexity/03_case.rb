class CaseForms
  # cc: 4 id: CaseForms#by_when
  def by_when(x)
    case x
    when Integer then :int
    when String then :str
    when nil then :nil
    else :other
    end
  end

  # cc: 3 id: CaseForms#by_in
  def by_in(x)
    case x
    in [a] then a
    in { k: } then k
    end
  end

  # cc: 4 id: CaseForms#guarded
  def guarded(x)
    case x
    in Integer if x > 0
      :pos
    in Integer
      :nonpos
    end
  end
end
