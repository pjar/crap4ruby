class SafeNav
  # cc: 2 id: SafeNav#single
  def single(user)
    user&.name
  end

  # cc: 4 id: SafeNav#chained
  def chained(order)
    order&.customer&.address&.city
  end

  # cc: 3 id: SafeNav#mixed
  def mixed(u)
    u&.profile ? u.profile.bio : nil
  end

  # Write forms (CRA-8 decision B): assignment fusion keeps the &. flag on
  # the call-write node, and rows are additive — the write row (when
  # counted) plus the &. row.
  # cc: 3 id: SafeNav#memoized
  def memoized(a)
    a&.cache &&= refresh(a)
  end

  # Operator-writes are free as their own operation: only the &. row adds.
  # cc: 2 id: SafeNav#bump_count
  def bump_count(a)
    a&.count += 3
  end

  # No chain discount through fused nodes: two &. plus the ||= row.
  # cc: 4 id: SafeNav#chained_default
  def chained_default(a)
    a&.b&.c ||= 1
  end

  # A plain safe attribute write is an ordinary safe CallNode.
  # cc: 2 id: SafeNav#assign
  def assign(a)
    a&.b = 1
  end

  # Safe index-write: the nested safe CallNode plus the IndexOrWriteNode —
  # direct safe index-writes (a&.[](i) ||= v) are unparseable syntax.
  # cc: 3 id: SafeNav#index_default
  def index_default(a, i, v)
    a&.b[i] ||= v
  end

  # Single-target contexts preserve the flag on CallTargetNode: the write
  # is skipped when the receiver is nil, so the branch counts.
  # cc: 3 id: SafeNav#assign_each
  def assign_each(a, xs)
    for a&.b in xs
    end
  end

  # cc: 3 id: SafeNav#capture_error
  def capture_error(a)
    begin
    rescue => a&.b
    end
  end
end
