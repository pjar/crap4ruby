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
end
