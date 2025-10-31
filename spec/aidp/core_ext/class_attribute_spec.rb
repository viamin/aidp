# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::CoreExt::ClassAttribute do
  # Define simple classes to exercise dynamic behavior
  before do
    stub_const("DummyBase", Class.new do
      class_attribute :setting, :feature_flag
    end)

    stub_const("DummyChild", Class.new(DummyBase))
  end

  it "defines reader on class returning nil initially" do
    expect(DummyBase.setting).to be_nil
    expect(DummyBase.feature_flag).to be_nil
  end

  it "allows setting and reading class attribute value" do
    DummyBase.setting = 42
    expect(DummyBase.setting).to eq(42)
  end

  it "inherits value from superclass when not yet defined" do
    DummyBase.setting = :inherited
    # Child has not set @setting yet; should read from superclass branch
    expect(DummyChild.setting).to eq(:inherited)
  end

  it "allows subclass to override inherited value" do
    DummyBase.setting = :base
    DummyChild.setting = :child_override
    expect(DummyBase.setting).to eq(:base)
    expect(DummyChild.setting).to eq(:child_override)
  end

  it "provides instance reader delegating to class" do
    DummyBase.setting = :instance_visible
    instance = DummyBase.new
    expect(instance.setting).to eq(:instance_visible)
  end

  it "raises error when attempting to set via instance" do
    instance = DummyBase.new
    expect {
      instance.setting = :invalid
    }.to raise_error(RuntimeError, /class attribute/)
  end

  it "supports multiple attributes defined in one call" do
    DummyBase.setting = :a
    DummyBase.feature_flag = true
    expect(DummyBase.setting).to eq(:a)
    expect(DummyBase.feature_flag).to be(true)
  end
end
