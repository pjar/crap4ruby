class MethodForms
  # cc: 1 id: MethodForms#initialize
  def initialize(name)
    @name = name
  end

  # cc: 1 id: MethodForms#name
  def name = @name

  # cc: 1 id: MethodForms#empty
  def empty; end

  # cc: 2 id: MethodForms.build
  def self.build(attrs)
    attrs ? new(attrs) : new({})
  end

  class << self
    # cc: 1 id: MethodForms.default
    def default
      new(nil)
    end
  end

  # cc: 2 id: MethodForms#==
  def ==(other)
    other.is_a?(self.class) && other.name == name
  end

  # cc: 1 id: MethodForms#name=
  def name=(value)
    @name = value
  end

  # no-row
  alias_method :title, :name
end
