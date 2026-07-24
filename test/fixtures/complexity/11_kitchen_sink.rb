class KitchenSink
  # cc: 12 id: KitchenSink#process
  def process(orders, opts = {})
    return [] if orders.nil?
    limit = opts[:limit] || 10
    seen = opts[:seen] ||= {}
    results = orders.take(limit).map do |o|
      case o.status
      when :new then o
      when :held then o if o.retry?
      else
        o.fallback&.dup
      end
    rescue StandardError
      nil
    end
    results.compact.each { |r| seen[r.id] = r }
    results.any? && results
  end
end
