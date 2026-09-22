RSpec.describe ViewingAs::Event, type: :model do
  let(:admin) { create_admin }
  let(:customer) { create_user(email_address: "customer@example.com") }

  def record(kind, detail: nil)
    described_class.record!(admin: admin, user: customer, kind: kind, detail: detail)
  end

  it "collapses page views inside the window, keyed on the detail" do
    record(ViewingAs::Kinds::READ)
    record(ViewingAs::Kinds::READ)
    record(ViewingAs::Kinds::READ, detail: "elsewhere")

    expect(described_class.where(kind: ViewingAs::Kinds::READ).count).to eq(2)
  end

  it "writes another page view once the window has passed" do
    record(ViewingAs::Kinds::READ)
    travel_to(ViewingAs.config.dedupe_window.from_now + 1.minute) { record(ViewingAs::Kinds::READ) }

    expect(described_class.where(kind: ViewingAs::Kinds::READ).count).to eq(2)
  end

  it "never collapses lifecycle rows" do
    2.times { record(ViewingAs::Kinds::START) }

    expect(described_class.where(kind: ViewingAs::Kinds::START).count).to eq(2)
  end

  it "records nothing without both parties" do
    expect(described_class.record!(admin: nil, user: customer, kind: ViewingAs::Kinds::START)).to be_nil
    expect(described_class.record!(admin: admin, user: nil, kind: ViewingAs::Kinds::START)).to be_nil
  end

  it "cannot be edited once written" do
    row = record(ViewingAs::Kinds::START)

    expect { row.update!(kind: ViewingAs::Kinds::STOP) }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "names the reviewer from the address recorded at the time" do
    row = record(ViewingAs::Kinds::START)
    admin.destroy!

    expect(row.reload.reviewer).to eq("admin@example.com")
    expect(row.description).to eq("Started viewing your account as you see it")
  end

  it "does not raise when the row cannot be written" do
    allow(described_class).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "no table")

    expect { record(ViewingAs::Kinds::START) }.not_to raise_error
  end
end
