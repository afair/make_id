# frozen_string_literal: true

RSpec.describe MakeId do
  describe "random" do
    it "generates the id" do
      expect(MakeId.id).to be > 0
    end

    it "converts bases" do
      id = MakeId.id
      id62 = MakeId.int_to_base(id)
      p [id, id62, MakeId.base_to_int(id62)]
      expect(MakeId.base_to_int(id62)).to eq(id)
    end
  end

  describe "uuid" do
    it "generates the uuid" do
      expect(MakeId.uuid).to match(/\A[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}\z/)
    end

    it "snowflake_uuid" do
      expect(MakeId.snowflake_uuid).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it "snowflake_datetime_uuid" do
      expect(MakeId.snowflake_datetime_uuid).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it "converts uuids to bases" do
      uuid = MakeId.uuid
      base10 = MakeId.uuid_to_base(uuid)
      base62 = MakeId.uuid_to_base(uuid, 62)
      expect(base10).to be > 0
      expect(base62.size).to be > 10
    end
  end

  describe "event_id" do
    it "generates the event_id" do
      expect(MakeId.event_id).to match(/\A[0-9A-Za-z]{12}\z/)
    end

    it "verifies check digit" do
      expect(MakeId.append_check_digit("1234567890")).to eq("12345678905")
    end
  end

  describe "nano_id" do
    it "generates the nano_id" do
      expect(MakeId.nano_id).to match(/\A[0-9A-Za-z]+\z/)
    end

    it "code" do
      expect(MakeId.code).to match(/\A[0-9A-Z]+\z/)
    end

    it "verify_code" do
      expect(MakeId.verify_code("1liO0a")).to eq("11100A")
    end

    it "request_id" do
      expect(MakeId.request_id.size).to eq(16)
    end
  end

  describe "snowflake_id" do
    it "generates the snowflake_id" do
      id = MakeId.snowflake_id(worker_id: 15)
      expect(id.to_s.size).to be > 10
    end

    it "makes base-62 flakes" do
      expect(MakeId.snowflake_id(worker_id: 0, base: 62).size).to be > 6
    end
  end

  it "has a version number" do
    expect(MakeId::VERSION).not_to be nil
  end
end
