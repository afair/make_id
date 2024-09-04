# frozen_string_literal: true

require_relative "make_id/version"
require "securerandom"
require "base64"
require "zlib"

# MakeID generates record Identifiers other than sequential integers.
# MakeId  - From the "make_id" gem found at https://github.com/afair/make_id
# License - MIT, see the LICENSE file in the gem's source code.
# Adopt   - Copy this file to your application with the above attribution to
#           allow others to find fixes, documentation, and new features.
module MakeId
  # class Error < StandardError; end

  CHARS32 = "0123456789abcdefghjkmnpqrstvwxyz" # Avoiding ambiguous 0/o i/l/I
  CHARS62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  EPOCH_TWITTER = Time.utc(2006, 3, 21, 20, 50, 14)

  @@app_worker_id = ENV.fetch("APP_WORKER_ID", 0)
  @@epoch = Time.utc(2020)
  @@counter_time = 0
  @@counter = 0

  # Set your default snowflake default id. This is a 10-bit number (0..1023)
  # that designates your: datacenter, machine, and/or process that generated it.
  # This can be overridden by setting the environment variable APP_WORKER_ID
  # or by the caller.
  # Usage (configuration): MakeId.app_worker_id = 123
  def self.app_worker_id=(id)
    @@app_worker_id = id.to_i & 0x3ff
  end

  # Returns the current worker id
  def self.app_worker_id
    @@app_worker_id
  end

  # Sets the start year for snowflake epoch
  def self.epoch=(arg)
    @@epoch = arg.is_a?(Time) ? arg : Time.utc(arg)
  end

  def self.epoch
    @@epoch
  end

  def self.application_epoch
    Time.now.to_i - @@epoch.to_i
  end

  ##############################################################################
  # Random Strings
  ##############################################################################

  # Returns a random alphanumeric string of the given base, default of 62.
  # Base 64 uses URL-safe characters. Bases 19-32 and below use a special
  # character set that avoids visually ambiguous characters. Other bases
  # utilize the full alphanumeric characer set (digits, lower/upper letters).
  def self.random(size = 16, base: 62)
    raise "Base must be between 2 and 62, or 64, not #{base}" unless base < 63 || base == 64
    if base == 62
      SecureRandom.alphanumeric(size)
    elsif base == 64
      SecureRandom.urlsafe_base64(size)
    else
      alpha = (base <= 32) ? CHARS32 : CHARS62
      (1..size).map { alpha[SecureRandom.rand(base - 1)] }.join
    end
  end

  ##############################################################################
  # Integers
  ##############################################################################

  # Random Integer ID
  def self.random_id(bytes: 8, base: 10, absolute: true, check_digit: false)
    id = SecureRandom.random_number(2**(bytes * 8) - 2) + 1 # +1 to avoid zero
    id = id.abs if absolute
    id = int_to_base(id, base) unless base == 10
    id = append_check_digit(id, base) if check_digit
    id
  end

  ##############################################################################
  # UUID - Universally Unique Identifier
  ##############################################################################

  # Returns a (securely) random generated UUID v4
  def self.uuid
    SecureRandom.uuid
  end

  # Accepts a hext UUID string and returns the integer value in the given base.
  # If base is specified, it will convert to that base using MakeId utilities.
  def self.uuid_to_base(uuid, base = 10)
    int = uuid.delete("-").to_i(16)
    (base == 10) ? int : int_to_base(int, base)
  end

  # Returns UUID with columnar date parts: yyyymmdd-hhmm-ssuu-uwww-rrrrrrrrrrrr
  # This is similar to a snowflake id but in a UUID format.
  def self.datetime_uuid(time: nil, format: true, worker_id: nil, utc: true)
    time ||= Time.new
    time = time.utc if utc
    worker_id ||= app_worker_id
    id = [
      time.year,
      time.month.to_s(16).rjust(2, "0"),
      time.day.to_s.rjust(2, "0"),
      time.hour.to_s.rjust(2, "0"),
      time.min.to_s.rjust(2, "0"),
      time.sec.to_s.rjust(2, "0"),
      (time.subsec.to_f * 1000).to_i.to_s(16).rjust(3, "0"),
      (worker_id % 1024).to_s(16).rjust(3, "0"),
      SecureRandom.hex(6)
    ].join
    format ? "#{id[0..7]}-#{id[8..11]}-#{id[12..15]}-#{id[16..19]}-#{id[20..31]}" : id
  end

  # Returns uuid with Unix epoch time sort in format: ssssssss-uuuw-wwrr-rrrr-rrrrrrrrrrrr
  # Specify `application_epoch: true` to use instead of Unix epoch
  # This is similar to a snowflake id but in a UUID format.
  def self.epoch_uuid(time: nil, format: true, worker_id: nil, application_epoch: false)
    time ||= Time.new
    seconds = time.to_i
    seconds -= @@epoch.to_i if application_epoch
    worker_id ||= app_worker_id
    parts = [
      seconds.to_s(16).rjust(8, "0"),
      (time.subsec.to_f * 1000).to_i.to_s(16).rjust(3, "0"),
      (worker_id % 1024).to_s(16).rjust(3, "0"),
      SecureRandom.hex(9)
    ]
    id = append_check_digit(parts.join, 16).downcase
    format ? "#{id[0..7]}-#{id[8..11]}-#{id[12..15]}-#{id[16..19]}-#{id[20..31]}" : id
  end

  ##############################################################################
  # Nano Id - Simple, secure URL-friendly unique string ID generator
  ##############################################################################

  # Generates a "nano id", a string of random characters of the given alphabet,
  # suitable for URL's or where you don't want to show a sequential number.
  # A check digit is added to the end to help prevent typos.
  def self.nano_id(size: 20, base: 62, check_digit: true)
    # alpha = (base <= 32) ? CHARS32 : CHARS62
    size -= 1 if check_digit
    id = random(size, base: base)
    check_digit ? append_check_digit(id, base) : id
  end

  # Given a nano_id, replaces visually ambiguous characters and verifies the
  # check digit. Returns the corrected id or nil if the check digit is invalid.
  def self.verify_nano32_id(nanoid)
    nanoid.gsub!(/[oO]/, "0")
    nanoid.gsub!(/[lLiI]/, "1")
    nanoid.downcase
    valid_check_digit?(nanoid, base: 32)
  end

  ##############################################################################
  # Event Id - A nano_id, but timestamped event identifier: YMDHMSUUrrrrc
  ##############################################################################

  # Returns an event timestamp of the form YMDHMSUUrrrrc
  def self.event_id(size: 12, check_digit: false, time: nil)
    time ||= Time.new.utc
    usec = int_to_base((time.subsec.to_f * 62 * 62).to_i, 62)
    parts = [
      CHARS62[time.year % @@epoch.year],
      CHARS62[time.month],
      CHARS62[time.day],
      CHARS62[time.hour],
      CHARS62[time.min],
      CHARS62[time.sec],
      usec.rjust(2, "0") # 2-chars, 0..3843
    ]
    nano_size = size - 8 - (check_digit ? 1 : 0)
    parts << nano_id(size: nano_size, base: 62) if nano_size > 0
    id = check_digit ? append_check_digit(parts.join, 62) : parts.join
    id[0, size]
  end

  # Returns a 16-character request id string in Base32 of format: YMDHsssuuqqwwrrr
  # Use substring [3, 8] (Hsssuuqq) for a short 8-character version, easier for human scanning.
  def self.request_id(time: nil, sequence_method: :counter)
    time ||= Time.new
    seconds = time.to_i - Time.new(time.year, time.month, time.day, time.hour).to_i # time.utc.hour??

    sequence = if sequence_method == :counter
      next_millisecond_sequence(((Time.now.utc.to_f - @@epoch.to_i) * 1000).to_i)
    elsif sequence_method == :random
      SecureRandom.random_number(4095)
    end

    [
      CHARS62[time.year % @@epoch.year],
      CHARS62[time.month],
      CHARS62[time.day], # "-",
      CHARS62[time.hour].downcase,
      int_to_base(seconds, 32).rjust(3, "0"), # 3 chars
      int_to_base((time.subsec.to_f * 32 * 32).to_i, 32), # 2 chars
      sequence.to_s(32).rjust(2, "0"), # 2 chars "-",
      (app_worker_id % 1024).to_s(32).rjust(2, "0"), # 2 chars
      random(3, base: 32)
    ].join
  end

  ##############################################################################
  # Snowflake Id - Epoch + millisecond + worker_id id + sequence number
  # Snowflakes are a form of unique identifier used in distributed computing.
  # Uses an epoch time with miliseconds (41 bits), a worker_id id of where it was
  # created (datacenter, machine, process, 10 bits), and a sequence number (12 bits).
  ##############################################################################

  # Returns an 8-byte integer snowflake id that can be reverse parsed.
  # sequence_counter can be :counter for a rotating integer, or :random
  def self.snowflake_id(worker_id: nil, base: 10, sequence_method: :counter)
    milliseconds = ((Time.now.utc.to_f - @@epoch.to_i) * 1000).to_i
    worker_id ||= app_worker_id
    sequence = 0
    if sequence_method == :counter
      sequence = next_millisecond_sequence(milliseconds)
    elsif sequence_method == :random
      sequence = SecureRandom.random_number(4095)
    end

    id = combine_snowflake_parts(milliseconds, worker_id, sequence)
    (base == 10) ? id : int_to_base(id, base)
  end

  # Creates the final snowflake by bit-mapping the constituent parts into the whole
  def self.combine_snowflake_parts(milliseconds, worker_id, sequence)
    id = milliseconds & 0x1ffffffffff # 0 (sign) + lower 41bits
    id <<= 10
    id |= worker_id & 0x3ff # 10bits (0..1023)
    id <<= 12
    id |= (sequence & 0xfff) # 12 bits (0..4095)

    id
  end

  def self.next_millisecond_sequence(milliseconds)
    sequence = 0
    semaphore = Mutex.new

    semaphore.synchronize do
      if @@counter_time != milliseconds
        @@counter_time = milliseconds
        @@counter = 0
      end
      sequence = @@counter % 4095
      @@counter += 1
    end

    sequence
  end

  # Build an integer value from pairs of [bits, value]
  def self.pack_int_parts(*pairs)
    int = 0
    pairs.each do |bits, value|
      int = (int << bits) | (value & ((1 << bits) - 1))
    end
    int
  end

  ##############################################################################
  # Base Conversions
  ##############################################################################

  # Takes an integer and a base (from 2 to 62) and converts the number.
  # Ruby's int.to_s(base) only goes to 36. Base 32 is special as it does not
  # contain visually ambiguous characters (1, not i, I, l, L) and (0, not o or O)
  # Which is useful for serial numbers or codes the user has to read or type
  def self.int_to_base(int, base = 62, check_digit: false)
    int = int.to_i
    if base == 10
      id = int.to_s
    elsif base == 64
      id = Base64.urlsafe_encode64(int.to_s).delete("=")
    elsif base == 32 || base > 36
      alpha = (base <= 32) ? CHARS32 : CHARS62
      id = ""
      while int > (base - 1)
        id = alpha[int % base] + id
        int /= base
      end
      id = alpha[int] + id
    else
      id = int.to_s(base)
    end
    check_digit ? append_check_digit(id, base) : id
  end

  singleton_class.alias_method :to_base, :int_to_base

  # Parses a string as a base n number and returns its decimal integer value
  def self.base_to_int(string, base = 62, check_digit: false)
    # TODO check_digit
    if base == 64
      int = Base64.urlsafe_decode64(string.to_s + "==")
    elsif base == 32 || base > 36
      alpha = (base <= 32) ? CHARS32 : CHARS62
      string = string.to_s
      int = 0
      string.each_char { |c| int = int * base + alpha.index(c) }
    else
      int = string.to_i(base)
    end
    int
  end

  singleton_class.alias_method :from_base, :base_to_int

  ##############################################################################
  # Check Digit
  ##############################################################################

  # Adds a check digit to the end of an id string. This check digit is derived
  # from the CRC-32 (Cyclical Redundancy Check) value of the id string
  def self.append_check_digit(id, base = 10)
    id.to_s + compute_check_digit(id, base)
  end

  # Returns a character computed using the CRC32 algorithm
  def self.compute_check_digit(id, base = 10)
    int_to_base(Zlib.crc32(id.to_s) % base, base)
  end

  # Takes an id with a check digit and return true if the check digit matches
  def self.valid_check_digit?(id, base = 10)
    id == append_check_digit(id[0..-2], base)
  end
end
