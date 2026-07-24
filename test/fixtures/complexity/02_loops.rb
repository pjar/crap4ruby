class Loops
  # cc: 2 id: Loops#count_down
  def count_down(n)
    while n > 0
      n -= 1
    end
    n
  end

  # cc: 2 id: Loops#drain
  def drain(q)
    q.pop until q.empty?
  end

  # cc: 2 id: Loops#sum_for
  def sum_for(xs)
    total = 0
    for x in xs
      total += x
    end
    total
  end

  # cc: 3 id: Loops#spin
  def spin(xs)
    i = 0
    i += 1 while i < xs.size
    loop do
      break
    end
    i
  end
end
