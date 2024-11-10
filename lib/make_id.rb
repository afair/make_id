# frozen_string_literal: true

require_relative "make_id/version"
require "securerandom"
require "zlib"

# MakeID generates record Identifiers other than sequential integers.
# MakeId  - From the "make_id" gem found at https://github.com/afair/make_id
# License - MIT, see the LICENSE file in the gem's source code.
# Adopt   - Copy this file to your application with the above attribution to
#           allow others to find fixes, documentation, and new features.
module MakeId
  class Error < StandardError; end

  # Base32 avoids ambiguous letters for 0/o/O and i/I/l/1. This is useful
  # for human-interpreted codes for serial numbers, license keys, etc.
  BASE32 = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

  # Ruby's Integer.to_s(2..36) uses extended Hexadecimal: 0-9,a-z.
  # Base62 includes upper-case letters as well, maintaining ASCII cardinality.
  BASE62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

  # Base64 Does not use ASCII-collating (sort) character set
  BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

  # Base94 extends Base64 with all printable ASCII special characters.
  # Using Base of 90 won't use quotes, backslash
  BASE94 = BASE64 + %q(!$%&()*,-.:;<=>?@[]^_{|}~#`'"\\)

  # URL-Encoded Base64 swaps the + and / for - and _ respectively to avoid URL Encoding
  URL_BASE64 = BASE64.tr("+/", "-_")

  # TWitter Snowflake starts its epoch at this time.
  EPOCH_TWITTER = Time.utc(2006, 3, 21, 20, 50, 14)

  @@app_worker_id = ENV.fetch("APP_WORKER_ID", 0)
  @@epoch = Time.utc(2020)
  @@counter_time = 0
  @@counter = 0
  @@check_proc = nil

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

  # Set a custom check digit proc that takes the id string and base as argumentsA
  # and returns a character to append to the end of the id.
  def self.check_proc=(proc)
    @@check_proc = proc
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
  def self.random(size = 16, base: 62, chars: nil)
    _, chars = base_characters(base, chars)
    SecureRandom.alphanumeric(size, chars: chars.chars)
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

  def self.random_id_password(bytes: 8, base: 10, absolute: true, alpha: nil)
    id = random_id(bytes: bytes)
    pass = random_id(bytes: 16)
    [int_to_base(id, base), encode_alphabet(pass, alpha || BASE94, seed: id)]
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

  ##############################################################################
  # Nano Id - Simple, secure URL-friendly unique string ID generator
  ##############################################################################

  # Generates a "nano id", a string of random characters of the given alphabet,
  # suitable for URL's or where you don't want to show a sequential number.
  # A check digit is added to the end to help prevent typos.
  def self.nano_id(size: 20, base: 62, check_digit: true)
    # alpha = (base <= 32) ? BASE32 : BASE62
    size -= 1 if check_digit
    id = random(size, base: base)
    check_digit ? append_check_digit(id, base) : id
  end

  # Given a nano_id, replaces visually ambiguous characters and verifies the
  # check digit. Returns the corrected id or nil if the check digit is invalid.
  def self.verify_base32_id(nanoid)
    nanoid.gsub!(/[oO]/, "0")
    nanoid.gsub!(/[lLiI]/, "1")
    nanoid.downcase
    valid_check_digit?(nanoid, base: 32)
  end

  # Manual Id is a code and/or identifier that is manually entered by a user.
  # Examples of this would be a Two-Factor Authentication challenge, a code
  # used for confirmation, redemption, or a short-term record lookup code
  # (like an airline ticket/itenerary code)
  # It uses a base-32 (non-ambiguous character set) by default,
  def self.manual_id(size: 6, base: 32, check_digit: false)
    base = 32 if base > 36 # For upcasing
    nano_id(size: size, base: base, check_digit: check_digit).upcase
  end

  def self.fix_manual_id(id, base: 32, check_digit: false)
    if base == 32
      id = id.gsub(/[oO]/, "0")
      id = id.gsub(/[lLiI]/, "1")
    end
    id = valid_check_digit?(id.downcase, base: 32) if check_digit
    id.upcase
  end

  ##############################################################################
  # TEMPORAL ID's
  ##############################################################################

  # Event Id - A nano_id, but timestamped event identifier: YMDHMSUUrrrrc
  def self.event_id(size: 12, check_digit: false, time: nil)
    time ||= Time.new.utc
    usec = int_to_base((time.subsec.to_f * 62 * 62).to_i, 62)
    parts = [
      BASE62[time.year % @@epoch.year],
      BASE62[time.month],
      BASE62[time.day],
      BASE62[time.hour],
      BASE62[time.min],
      BASE62[time.sec],
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
      BASE62[time.year % @@epoch.year],
      BASE62[time.month],
      BASE62[time.day], # "-",
      BASE62[time.hour].downcase,
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

  # Returns uuid with Unix epoch time sort in format: ssssssss-uuuw-wwrr-rrrr-rrrrrrrrrrrr
  # Specify `application_epoch: true` to use instead of Unix epoch
  def self.snowflake_uuid(time: nil, format: true, worker_id: nil, application_epoch: false)
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

  # Returns UUID with columnar date parts: yyyymmdd-hhmm-ssuu-uwww-rrrrrrrrrrrr
  def self.snowflake_datetime_uuid(time: nil, format: true, worker_id: nil, utc: true)
    time ||= Time.new
    time = time.utc if utc
    worker_id ||= app_worker_id
    id = [
      time.year,
      time.month.to_s.rjust(2, "0"),
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
  def self.int_to_base(int, base = 62, check_digit: false, chars: nil)
    base, chars = base_characters(base, chars)
    id = encode_alphabet(int, chars)
    check_digit ? append_check_digit(id, base) : id
  end

  singleton_class.alias_method :to_base, :int_to_base

  # Parses a string as a base n number and returns its decimal integer value
  def self.base_to_int(string, base = 62, check_digit: false)
    # TODO check_digit
    _, chars = base_characters(base, chars)
    decode_alphabet(string, chars)
  end

  singleton_class.alias_method :from_base, :base_to_int

  def self.encode_alphabet(int, alpha = BASE62, seed: nil)
    base = alpha.size
    alpha = alpha.chars.shuffle(random: Random.new(seed)).join if seed
    id = ""
    while int > (base - 1)
      id = alpha[int % base] + id
      int /= base
    end
    alpha[int] + id
  end

  def self.decode_alphabet(string, alpha = BASE32, seed: nil, base: nil)
    base ||= alpha.size
    alpha = alpha.chars.shuffle(random: Random.new(seed)).join if seed
    int = 0
    string.each_char { |c| int = int * base + alpha.index(c) }
    int
  rescue
    nil
  end

  # Returns the refined base and characters used for the base conversions
  def self.base_characters(base, chars = nil, shuffle_seed: nil)
    if chars
      base ||= chars.size
      chars = chars[0..(base - 1)]
    elsif base > 94 || base < 2
      raise Error.new("Base#{base} is not supported")
    elsif base > 64
      chars = BASE94[0..(base - 1)]
    elsif base > 62
      chars = URL_BASE64[0..(base - 1)]
    elsif base == 32
      chars = BASE32
    else
      chars = BASE62[0..(base - 1)]
    end
    if shuffle_seed
      chars = chars.chars.shuffle(random: Random.new(shuffle_seed)).join
    end
    base = chars.size

    [base, chars]
  end

  ##############################################################################
  # Check Digit
  ##############################################################################

  # Adds a check digit to the end of an id string. This check digit is derived
  # from the CRC-32 (Cyclical Redundancy Check) value of the id string
  def self.append_check_digit(id, base = 10)
    id.to_s + compute_check_digit(id, base)
  end

  # Returns a character computed using the CRC32 algorithm
  # Uses a pre-defined check_proc if configured. See check_proc=().
  def self.compute_check_digit(id, base = 10)
    return @@check_proc.call(id, base) if @@check_proc.is_a?(Proc)
    int_to_base(Zlib.crc32(id.to_s) % base, base)
  end

  # Takes an id with a check digit and return true if the check digit matches
  def self.valid_check_digit?(id, base = 10)
    id == append_check_digit(id[0..-2], base)
  end
end
