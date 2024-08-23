# frozen_string_literal: true

RSpec.describe MakeId do
  describe "event_id" do
    it "generates the event_id" do
      expect(MakeId.event_id).to match(/\A[0-9A-Za-z]{12}\z/)
    end
  end

  it "has a version number" do
    expect(MakeId::VERSION).not_to be nil
  end
end
