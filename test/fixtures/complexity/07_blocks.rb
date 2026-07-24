class Blocks
  # cc: 2 id: Blocks#names
  def names(users)
    users.map { |u| u.name }
  end

  # cc: 3 id: Blocks#deep
  def deep(groups)
    groups.each do |g|
      g.users.each { |u| u }
    end
  end

  # cc: 2 id: Blocks#shorthand
  def shorthand(users)
    users.map(&:name)
  end

  # cc: 2 id: Blocks#forward
  def forward(users, &blk)
    users.each(&blk)
  end

  # cc: 2 id: Blocks#numbered
  def numbered(xs)
    xs.map { _1 * 2 }
  end

  # cc: 2 id: Blocks#with_it
  def with_it(xs)
    xs.select { it.odd? }
  end

  # cc: 3 id: Blocks#callbacks
  def callbacks
    on_save = ->(rec) { rec.touch }
    fallback = proc { :noop }
    [on_save, fallback]
  end
end
