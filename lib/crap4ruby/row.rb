module Crap4Ruby
  # §8's gate value, as an exact Rational: a Float 8.0 comparison rounds
  # away a max within half an ulp of 8. §11.2/§11.3 compare against the
  # same constant, so the ratchet and the plain gate cannot disagree.
  THRESHOLD = Rational(8)

  # One scored method (spec §1, §7.1). `cov` arrives as a Rational and
  # `crap` stays Rational: the gate compares unrounded values and the
  # report rounds half-up (§8), so no binary float error is introduced.
  Row = Struct.new(:method, :units, :hits, :cov, keyword_init: true) do
    # The metric itself, in one place: §7.1's cov and §1's CRAP. §11.2
    # recomputes a baseline row's stored components through these same two
    # functions, so a ratchet comparison can never drift from the gate.
    def self.cov_for(units:, hits:, called:)
      units.positive? ? Rational(hits, units) : Rational(called ? 1 : 0)
    end

    def self.crap_for(comp:, cov:) = comp**2 * (1 - cov)**3 + comp

    def crap = self.class.crap_for(comp: method.comp, cov: cov)

    # §7.2: the invocation bit is consulted only at zero units, so it is
    # false for every row that has units — which is exactly the `called`
    # value §11.4 stores.
    def invoked? = units.zero? && cov == 1
  end
end
