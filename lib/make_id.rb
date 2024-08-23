# frozen_string_literal: true

require_relative "make_id/version"
require "SecureRandom"

# MakeID generates record Identifiers other than sequential integers.
module MakeId
  class Error < StandardError; end

  # Your code goes here...
  CHARS32 = "0123456789abcdefghjkmnpqrstvwxyz" # Avoiding ambiguous 0/o i/l/I
  CHARS62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  EVENT_START_YEAR = 2020
  UUID_START_YEAR = 2000
  @@snowflake_source_id = 0

  ##############################################################################
  # UUID - Universally Unique Identifier
  ##############################################################################

  # Returns a (securely) random generated UUID v4
  def self.uuid
    SecureRandom.uuid
  end

  # Returns UUID with columnar date parts : yymddhhm-mssu-uurr-rrrrrrrc
  def self.datetime_uuid(time: nil, format: true)
    time ||= Time.new.utc
    parts = [
      (time.year % UUID_START_YEAR).to_s(16),
      time.month.to_s(16),
      time.day.to_s(16).rjust(2, "0"),
      time.hour.to_s(16).rjust(2, "0"),
      time.min.to_s(16).rjust(2, "0"),
      time.sec.to_s(16).rjust(2, "0"),
      (time.subsec.to_f * 4095).to_i.to_s(16).rjust(3, "0"),
      SecureRandom.uuid.delete("-")[0, 17]
    ]
    id = check_digit(parts.join, base: 16).downcase
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
    id = check_digit(parts.join, base: 16).downcase
    format ? "#{id[0..7]}-#{id[8..11]}-#{id[12..15]}-#{id[16..19]}-#{id[20..31]}" : id
  end

  ##############################################################################
  # Nano Id - Simple, secure URL-friendly unique string ID generator
  ##############################################################################

  # Generates a "nano id", a string of random characters of the given alphabet,
  # suitable for URL's or where you don't want to show a sequential number.
  # A check digit is added to the end to help prevent typos.
  def self.nano_id(size = 20, base: 62, check_digit: true, seed: nil)
    alpha = (base <= 32) ? CHARS32 : CHARS62
    size -= 1 if check_digit
    id = (1..size).map { alpha[rand(base - 1)] }.join
    check_digit ? check_digit(id, base: base) : id
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
    id += nano_id(size - z - 1, base: base) + to_base(z, base)
    check_digit ? check_digit(id, base: base) : id
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

  # Returns an event timestamp of the form YMDHMSUUrrrrrrrc
  def self.event_id(size: 16, usec_size: 2, nano_size: 4, check_digit: false, time: nil)
    time ||= Time.new.utc
    usec = to_base((time.subsec.to_f * 62 * 62).to_i)
    parts = [
      CHARS62[time.year % EVENT_START_YEAR],
      CHARS62[time.month],
      CHARS62[time.day],
      CHARS62[time.hour],
      CHARS62[time.min],
      CHARS62[time.sec],
      usec.rjust(usec_size, "0"),
      nano_id(nano_size, base: 62)
    ]
    # p parts
    id = parts.join
    check_digit ? check_digit(id) : id
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

  # Returns an 8-byte integer snowflake id that can be reverse parsed.
  def self.snowflake_id(source_id = nil, base: 10)
    source_id ||= ENV["SNOWFLAKE_SOURCE_ID"] || snowflake_source_id
    bits = (Time.now.utc.to_f * 1000).to_i.to_s(2) # 41 bits
    bits += source_id.to_i.to_s(2).rjust(10, "0")[0, 12] # first 10 bits
    bits += SecureRandom.random_number(4095).to_s(2).rjust(12, "0") # 12 bits
    id = bits.to_i(2) # Convert binary to 8-byte integer
    (base == 10) ? id : to_base(id, base)
  end

  ##############################################################################
  # Obscure Id - Base62 integer with check digit
  ##############################################################################

  # Takes a traditional integer id number and returns a string that can
  # be used to prevent id guessing in URL's
  def self.obscure_id(int, base: 32, transform: true)
    int = ((((int * 17) - 3) * 57) + 73) if transform
    id = to_base(int, base)
    check_digit(id, base: base)
  end

  # Takes an obscure_id created here and returns the encoded original integer value
  def self.decode_obscure_id(id, base: 32, transform: true)
    return nil unless id == check_digit(id[0..-2], base: base)
    id = id[0..-2]
    int = from_base(id, base: base)
    transform ? ((((int - 73) / 57) + 3) / 17) : int
  end

  ##############################################################################
  # Base Conversions
  ##############################################################################

  # Takes an integer and a base (from 2 to 62) and converts the number.
  # Ruby's int.to_s(base) only goes to 36. Base 32 is special as it does not
  # contain visually ambiguous characters (1, not i, I, l, L) and (0, not o or O)
  # Which is useful for serial numbers or codes the user has to read or type
  def self.to_base(int, base = 62, check_digit: false)
    int = int.to_i
    alpha = (base <= 32) ? CHARS32 : CHARS62
    id = ""
    while int > (base - 1)
      id = alpha[int % base] + id
      int /= base
    end
    id = alpha[int] + id
    check_digit ? check_digit(id) : id
  end

  # Parses a string as a base n number and returns its decimal integer value
  def self.from_base(id, base = 62)
    alpha = (base <= 32) ? CHARS32 : CHARS62
    id = id.to_s
    int = 0
    id.each_char { |c| int = int * base + alpha.index(c) }
    int
  end

  ##############################################################################
  # Check Digit
  ##############################################################################

  # Adds a check digit to the end of an id string
  def self.check_digit(id, base: 62)
    sum = 0
    id.each_char { |c| sum += c.ord }
    id += CHARS62[sum % base]
    id
  end

  # Takes an id with a check digit and return true if the check digit matches
  def self.valid_check_digit?(id, base: 62)
    id == check_digit(id[0..-2], base: base)
  end
end
