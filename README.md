# MakeId

MakeID is a ruby library containing data record identifier generators. Perhaps it is a library of _identifier patterns_?
Let me know (by pull request) if you have any useful standard (or should be) id types.

Most databases use a sequential, auto-incrementing number as the primary key. For example, in PostgreSQL this is implemented using sequences.

Not every data "id" wants to use sequential numbers. These can be easy to guess and allow inpection of random records by altering the URL.

## Installation

This is a gem, and is installed as such:

    gem install make_id

or by placing in your Gemfile, or running this bundler command:

    bundle add make_id

Alternatively, you can skip the dependency and "adopt" the primary file within this repo, `lib/make_id.rb`,
keeping the attribution comments to find upstream documentation, fixes, and new features.

Another good alternative to using sequential id's is an alternate or external id used for URL's. This external
id can be generated id of any of these schemes, along with a unique index on the column. This gives you the ease
of a standard sequential id, with the security of a randomly-generated identifier.

When storing a string key in the database, look at using fixed-size columns instead of "characer varying" strings
as these have an additional cost of storing the length (PostgreSQL uses 4 bytes). Also, consider index performance
as these id's will likely require a unique index.

## Usage

Sequential Id's are great, and perform well in most cases. Here are a few alternatives to find here.

### Base conversions and Check Digits

Larger numbers can be represented more compactly with a larger base or radix. MakeId has utilities to
convert to and from its supported bases. You can leverage these for URL Id's to avoid long or simple
numeric codes.

Bases supported are:

- Base94: Base64 (Upper, Lower, Digits) with 30 extra special characters
- Base64: Url-Safe version. Base64 but swaps the plus and slash by dash and underscore respectively.
- Base62: digits, upper, and lower-case letters. No special characters. The default.
- Base32: digits and upper case without ambiguous characters "1lI" or "oO0"
- Base 2 through 36 (except 32): Ruby's `Integer#to_s(base)` is used

The Base32 may seem out of place, but is useful for alpha-numeric codes the users are required to type or speak,
such as serial numbers or license codes.
All letters are upper-case, and ambiguous characters are converted to the canonical ones.

    MakeId.int_to_base(123456789, 32) #=> "3NQK8N"
    MakeId.from_base("3NQK8N", 10)    #=> 123456789
    MakeId.int_to_base(123456789, 32) #=> "3NQK8N"
    MakeId.verify_base32_id("...")    #=> corrected_id or nil if error

### Random Integer

MakeId can return a random (8-byte by default) integer. You can request it returned in a supported base,
and with an optional check_digit.
Usually, you would use the integer returned, and call `int_to_base` to format for a URL or code.

    MakeId.id() #=> 15379918763975837985ZZ
    MakeId.id(base: 62, check_digit: true) #=> "2984biEwRT1"

Nano Id's are shorter unique strings generated from random characters, usually as a friendlier alternative
to UUID's. These are 8-byte numeric identifiers in extended bases, such as 36 or 62.

    MakeId.nano_id()         #=> "iZnLn96FVcjivEJA" (Base-62 be default)
    MakeId.nano_id(base: 36) #=> "sf8kqb8ekn7k98rq"

### UUID

UUID are 16-byte numbers, usually represented in hexadecimal of the format `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`.
There are different schemes for UUID types, and each has it's use. Most record Id's use a randomly generated UUID,
which if very unlikely (but possible) to have collitions with existing keys. The `uuid_to_base` helper method
can be used to transform a long UUID into a possibly more palettable base representation.

    u = MakeId.uuid #=> "1601125f-ee7c-4c0b-b693-dd2265edbcfc"
    MakeId.uuid_to_base(u, 10) #=> 29248580887982686871727313613986053372 (38 characters)
    MakeId.uuid_to_base(u, 62) #=> "fWJtuXEQJnkjxroWjkmei" (21 characters)

Note that some databases support a UUID type which makes storing UUID's easier, and since they are stored as a binary
field, consume less space.

### Tokens

Tokens are randomly-generated strings of the character set of the requested base.
The default size is 16 characters of the Base-62 character set.

    MakeId.token() #=> "Na4VX61PBFVZWL6Y"
    MakeId.token(8, base:36) #=> "BK0ZTL9H"

### Codes

Codes are string tokens to send to users for input. They have no ambiguous characters to avoid confusion.
This is useful for verifications such as two-factor authentication codes, or license numbers.
This returns an 8-character string by default. Specify a group (size) and delimiter (default is a hyphen)
to make long codes readable.

    MakeId.code #=> "22E0D18F"
    MakeId.code(20) #=> "Y41Q24AG7DYZYTAZWQZX"
    MakeId.code(20, group: 4, delimiter: "-") #=> "9975-V5VM-KKSR-4PQ6-7F4G"

### Temporal Identifiers

A `request_id` is a nano_id that can be used to track requests and jobs. It is a 16-byte string, the same
storage as a UUID, but with columnar values. The substring of 3 for 8 is a short (8 character) version that
can be used as well, is easier to read, sortable within a day, and unique enough to work with.

    id = MakeId.request_id #=> "494f1272t01000c4"
    #-------------------------->YMDHsssuuqqwwrrr
    id[3,8]                #=> "f1272t01"
    #-------------------------->Hsssuuqq

Snowflake Id's were invented at Twitter to stamp an identifier for a tweet or direct message.
It is an 8-byte integer intended to be time-sorted and unique across the fleet of servers saving messages.
It is a bit-mapped integer consisting of these parts:

- "Application Epoch" milliseconds (number of seconds since the designated start). positive sign and 41 bits.
- "Worker Id", a number from 0..1023 (10 bits) used to designate the datacenter, server, and/or process generating the id.
- "Sequence Id", a number from 0..4095 (12 bits) of messages within the given millisecond, or a random number within.

The application epoch is the start time before data was generated. This is set by passing a year integer or Time object.
The default is 2020 for the library. Because there are only 41 bits for the `time * 1000` (milliseconds),
higher order bits are removed. Therefore, limit the size of your epoch to a later date to keep the id's sortable as well as readable.

    MakeId.epoch = 2020 # or Time.utc(2020)
    MakeId.snowflake_id => 618906575771271168
    #--------------------->eeeeeeeeeeuuussrrr (Bit breakdown for understanding, not to scale)

The `worker_id` defaults to 0 and can be set with the APP_WORKER_ID environment variable or call
to a setter at the startup of the application. Set with a number appropriate for your environment.

You can also pass in options to return it as a different base, and with a check digit.

    MakeId.app_worker_id = 234
    MakeId.snowflake_id => 618905333721374720
    MakeId.snowflake_id(worker_id: 12, base: 32, sequence_method: :random) #=> "2TMXK6NE81JD5"

The `snowflake_uuid` method provides a time-based identifier, great for sorting just as sequential numbers, but unique enough to fit the bill.

    MakeId.snowflake_uuid # w> "66d735c6-0be2-6517-da69-57d440987c18"
    u = MakeId.snowflake_uuid #=> "66d735e6-7ac4-8bfc-5af0-39b4e2c96b05"
    #------------------------->eeeeeeee-uuuw-wwrr-rrrr-rrrrrrrrrrrr

Want a ISO-like readable timestamp in your UUID? The `snowflake_datetime_uuid` method combines elements of the
snowflake id (below) and the human-readable ISO timestamp in the UUID. Also includes milliseconds,
the "worker id" for the snowflake id, and a randomized 12-byte field. This could be useful for time-series
records or when you need a slowflake ID but have a UUID column to fill.

    MakeID.snowflake_datetime_uuid #=> "20240904-1418-5332-2000-3a38e61d5582"
    #------------------------>YYYYMMDD-hhmm-ssuu-uwww-rrrrrrrrrrrr

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/afair/make_id. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/afair/make_id/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the MakeId project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/afair/make_id/blob/main/CODE_OF_CONDUCT.md).
