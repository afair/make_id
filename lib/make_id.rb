# frozen_string_literal: true

require_relative "make_id/version"
require "SecureRandom"
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

  @@snowflake_source_id = ENV.fetch("SNOWFLAKE_SOURCE_ID", 0)
  @@epoch = Time.utc(2020)
  @@counter_time = 0
  @@counter = 0

  ##############################################################################
  # Integers
  ##############################################################################

  # Random Integer ID
  def self.random_id(bytes: 8, base: 10, absolute: true, check_digit: false)
    id = SecureRandom.random_number(2**(bytes * 8) - 2) + 1 # +1 to avoid zero
    id = id.abs if absolute
    id = to_base(id, base) unless base == 10
    id = append_check_digit(id, base) if check_digit
    id
  end

  # Takes a traditional integer id number and returns a string that can
  # be used to prevent id guessing in URL's. Experimental!
  def self.obscure_id(int, base: 32, transform: true)
    int = ((((int * 17) - 3) * 57) + 73) if transform
    id = to_base(int, base)
    append_check_digit(id, base)
  end

  # Takes an obscure_id created here and returns the encoded original integer value.
  # Experimental!
  def self.decode_obscure_id(id, base: 32, transform: true)
    return nil unless id == append_check_digit(id[0..-2], base)
    id = id[0..-2]
    int = from_base(id, base: base)
    transform ? ((((int - 73) / 57) + 3) / 17) : int
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
    (base == 10) ? int : to_base(int, base)
  end

  # Returns UUID with columnar date parts : yymddhhm-mssu-uurr-rrrrrrrc
  def self.datetime_uuid(time: nil, format: true)
    time ||= Time.new.utc
    parts = [
      (time.year % @@epoch.year).to_s(16),
      time.month.to_s(16),
      time.day.to_s(16).rjust(2, "0"),
      time.hour.to_s(16).rjust(2, "0"),
      time.min.to_s(16).rjust(2, "0"),
      time.sec.to_s(16).rjust(2, "0"),
      (time.subsec.to_f * 4095).to_i.to_s(16).rjust(3, "0"),
      SecureRandom.uuid.delete("-")[0, 17]
    ]
    id = append_check_digit(parts.join, 16).downcase
    format ? "#{id[0..7]}-#{id[8..11]}-#{id[12..15]}-#{id[16..19]}-#{id[20..31]}" : id
  end

  # Returns uuid with epoch time sort in format: ssssssss-uuur-rrrr-rrrrrrrc
  def self.epoch_uuid(time: nil, format: true)
    time ||= Time.new.utc
    parts = [
      time.to_i.to_s(16).rjust(8, "0"),
      (time.subsec.to_f * 4095).to_i.to_s(16).rjust(3, "0"),
      SecureRandom.uuid.delete("-")[0, 20]
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
  def self.nano_id(size: 20, base: 62, check_digit: true, seed: nil)
    alpha = (base <= 32) ? CHARS32 : CHARS62
    size -= 1 if check_digit
    id = (1..size).map { alpha[SecureRandom.rand(base - 1)] }.join
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

  # Returns a nano_id with id mapped within: "iiinnnnnnnnzc" where "iii" is the
  # id in the given base, "nnnn" is the nano_id, and "z" is the length of the id,
  # and "c" is a check digit.
  def self.hybrid_nano_id(int, size: 10, base: 62, check_digit: true)
    id = to_base(int, base)
    z = id.length
    id += nano_id(size: size - z - 1, base: base) + to_base(z, base)
    check_digit ? append_check_digit(id, base) : id
  end

  def self.parse_hybrid_nano_id(id, base: 62)
    return nil unless valid_check_digit?(id, base: base)
    z = from_base(id[-1], base: base)
    id = id[0, z]
    from_base(id, base)
  end

  ##############################################################################
  # Event Id - A nano_id, but timestamped event identifier: YMDHMSUUrrrrc
  ##############################################################################

  # Returns an event timestamp of the form YMDHMSUUrrrrc
  def self.event_id(size: 12, check_digit: false, time: nil)
    time ||= Time.new.utc
    usec = to_base((time.subsec.to_f * 62 * 62).to_i, 62)
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

  # MDHMSUrr
  def self.request_id(size = 16)
  end

  ##############################################################################
  # Snowflake Id - Epoch + millisecond + source id + sequence number
  # Snowflakes are a form of unique identifier used in distributed computing.
  # Uses an epoch time with miliseconds (41 bits), a source id of where it was
  # created (datacenter, machine, process, 10 bits), and a sequence number (12 bits).
  ##############################################################################

  # Set your default snowflake default id. This is a 10-bit number (0..1023)
  # that designates your: datacenter, machine, and/or process that generated it.
  # This can be overridden by setting the environment variable SNOWFLAKE_SOURCE_ID
  # or by the caller.
  # Usage (configuration): MakeId.snowflake_source_id = 123
  def self.snowflake_source_id=(id)
    @@snowflake_source_id = id.to_i & 0x3ff
  end

  # Returns the current snowflake source id
  def self.snowflake_source_id
    @@snowflake_source_id
  end

  # Sets the start year for snowflake epoch
  def self.epoch=(arg)
    @@epoch = arg.is_a?(Time) ? arg : Time.utc(arg)
  end

  def self.epoch
    @@epoch
  end

  # Returns an 8-byte integer snowflake id that can be reverse parsed.
  # sequence_counter can be :counter for a rotating integer, or :random
  def self.snowflake_id(source_id: nil, base: 10, sequence_method: :counter)
    milliseconds = ((Time.now.utc.to_f - @@epoch.to_i) * 1000).to_i
    source_id ||= snowflake_source_id
    sequence = 0
    if sequence_method == :counter
      sequence = next_millisecond_sequence(milliseconds)
    elsif sequence_method == :random
      sequence = SecureRandom.random_number(4095)
    end

    id = combine_snowflake_parts(milliseconds, source_id, sequence)
    (base == 10) ? id : to_base(id, base)
  end

  # Creates the final snowflake by bit-mapping the constituent parts into the whole
  def self.combine_snowflake_parts(milliseconds, source_id, sequence)
    id = milliseconds & 0x1ffffffffff # 0 (sign) + lower 41bits
    id <<= 10
    id |= source_id & 0x3ff # 10bits (0..1023)
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
    to_base(Zlib.crc32(id.to_s) % base, base)
  end

  # Takes an id with a check digit and return true if the check digit matches
  def self.valid_check_digit?(id, base = 10)
    id == append_check_digit(id[0..-2], base)
  end
end
