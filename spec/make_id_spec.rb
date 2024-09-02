# frozen_string_literal: true

RSpec.describe MakeId do
  describe "random" do
    it "generates the id" do
      expect(MakeId.random_id).to be > 0
    end

    it "converts bases" do
      id = MakeId.random_id
      id62 = MakeId.int_to_base(id)
      expect(MakeId.base_to_int(id62)).to eq(id)
    end
  end

  describe "uuid" do
    it "generates the uuid" do
      expect(MakeId.uuid).to match(/\A[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}\z/)
    end

    it "epoch_uuid" do
      expect(MakeId.epoch_uuid).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
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
      expect(MakeId.nano_id).to match(/\A[0-9A-Za-z]{20}\z/)
    end
  end

  describe "snowflake_id" do
    it "generates the snowflake_id" do
      id = MakeId.snowflake_id(source_id: 15)
      expect(id.to_s.size).to be > 10
    end

    it "makes base-62 flakes" do
      # 1000.times { p(MakeId.snowflake_id(source_id: 15, base: 64)) }
      expect(MakeId.snowflake_id(source_id: 0, base: 62).size).to be > 6
    end
  end

  it "has a version number" do
    expect(MakeId::VERSION).not_to be nil
  end
end
