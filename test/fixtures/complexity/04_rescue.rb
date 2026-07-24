class Rescues
  # cc: 3 id: Rescues#guarded_parse
  def guarded_parse(io)
    begin
      io.read
    rescue IOError
      :io
    rescue ArgumentError => e
      e.message
    else
      :ok
    ensure
      io.close
    end
  end

  # cc: 2 id: Rescues#soft
  def soft(x)
    Integer(x) rescue 0
  end

  # cc: 2 id: Rescues#def_level
  def def_level(path)
    File.read(path)
  rescue Errno::ENOENT
    ""
  end
end
