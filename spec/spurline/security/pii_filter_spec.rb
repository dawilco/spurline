# frozen_string_literal: true

RSpec.describe Spurline::Security::PIIFilter do
  def content(text, trust: :user, source: "test")
    Spurline::Security::Content.new(text: text, trust: trust, source: source)
  end

  describe "#initialize" do
    it "defaults to :off mode" do
      filter = described_class.new
      expect(filter.mode).to eq(:off)
    end

    it "accepts all valid modes" do
      %i[redact block warn off].each do |mode|
        filter = described_class.new(mode: mode)
        expect(filter.mode).to eq(mode)
      end
    end

    it "raises ConfigurationError for invalid mode" do
      expect {
        described_class.new(mode: :invalid)
      }.to raise_error(Spurline::ConfigurationError, /Invalid PII filter mode/)
    end
  end

  describe "#detect" do
    let(:filter) { described_class.new(mode: :redact) }

    it "detects email addresses" do
      detections = filter.detect("Contact me at user@example.com")
      expect(detections.any? { |d| d[:type] == :email }).to be true
    end

    it "detects phone numbers" do
      detections = filter.detect("Call me at 555-123-4567")
      expect(detections.any? { |d| d[:type] == :phone }).to be true
    end

    it "detects phone numbers with parentheses" do
      detections = filter.detect("Call (555) 123-4567")
      expect(detections.any? { |d| d[:type] == :phone }).to be true
    end

    it "detects phone numbers with country code" do
      detections = filter.detect("Call +1-555-123-4567")
      expect(detections.any? { |d| d[:type] == :phone }).to be true
    end

    it "detects SSN" do
      detections = filter.detect("My SSN is 123-45-6789")
      expect(detections.any? { |d| d[:type] == :ssn }).to be true
    end

    it "detects credit card numbers" do
      detections = filter.detect("Card: 4111 1111 1111 1111")
      expect(detections.any? { |d| d[:type] == :credit_card }).to be true
    end

    it "detects credit card numbers with dashes" do
      detections = filter.detect("Card: 4111-1111-1111-1111")
      expect(detections.any? { |d| d[:type] == :credit_card }).to be true
    end

    it "detects IP addresses" do
      detections = filter.detect("Server at 192.168.1.100")
      expect(detections.any? { |d| d[:type] == :ip_address }).to be true
    end

    it "detects multiple PII types in one string" do
      text = "Email me at user@example.com or call 555-123-4567"
      detections = filter.detect(text)
      types = detections.map { |d| d[:type] }.uniq
      expect(types).to include(:email, :phone)
    end

    it "returns empty array for clean text" do
      detections = filter.detect("This is a normal message with no PII")
      expect(detections).to be_empty
    end
  end

  describe "#filter" do
    context "with :off mode" do
      let(:filter) { described_class.new(mode: :off) }

      it "returns the content unchanged" do
        c = content("email: test@example.com")
        result = filter.filter(c)
        expect(result).to eq(c)
      end

      it "does not scan for PII" do
        c = content("SSN: 123-45-6789")
        result = filter.filter(c)
        expect(result.text).to include("123-45-6789")
      end
    end

    context "with :redact mode" do
      let(:filter) { described_class.new(mode: :redact) }

      it "replaces email addresses with placeholder" do
        c = content("Contact user@example.com for info")
        result = filter.filter(c)
        expect(result.text).to include("[REDACTED_EMAIL]")
        expect(result.text).not_to include("user@example.com")
      end

      it "replaces phone numbers with placeholder" do
        c = content("Call 555-123-4567 for help")
        result = filter.filter(c)
        expect(result.text).to include("[REDACTED_PHONE]")
        expect(result.text).not_to include("555-123-4567")
      end

      it "replaces SSN with placeholder" do
        c = content("SSN is 123-45-6789")
        result = filter.filter(c)
        expect(result.text).to include("[REDACTED_SSN]")
        expect(result.text).not_to include("123-45-6789")
      end

      it "replaces credit card numbers with placeholder" do
        c = content("Card: 4111 1111 1111 1111")
        result = filter.filter(c)
        expect(result.text).to include("[REDACTED_CREDIT_CARD]")
        expect(result.text).not_to include("4111")
      end

      it "replaces IP addresses with placeholder" do
        c = content("Server at 192.168.1.100")
        result = filter.filter(c)
        expect(result.text).to include("[REDACTED_IP]")
        expect(result.text).not_to include("192.168.1.100")
      end

      it "replaces multiple PII types" do
        c = content("Email user@example.com, call 555-123-4567, SSN 123-45-6789")
        result = filter.filter(c)
        expect(result.text).to include("[REDACTED_EMAIL]")
        expect(result.text).to include("[REDACTED_PHONE]")
        expect(result.text).to include("[REDACTED_SSN]")
      end

      it "returns a new Content object" do
        c = content("email: test@example.com")
        result = filter.filter(c)
        expect(result).not_to equal(c)
        expect(result).to be_a(Spurline::Security::Content)
      end

      it "preserves trust level" do
        c = content("email: test@example.com", trust: :external)
        result = filter.filter(c)
        expect(result.trust).to eq(:external)
      end

      it "preserves source" do
        c = content("email: test@example.com", source: "tool:search")
        result = filter.filter(c)
        expect(result.source).to eq("tool:search")
      end

      it "returns content unchanged when no PII is found" do
        c = content("Just a normal message")
        result = filter.filter(c)
        expect(result).to eq(c)
      end

      it "returns the redacted Content object frozen" do
        c = content("email: test@example.com")
        result = filter.filter(c)
        expect(result).to be_frozen
      end
    end

    context "with :block mode" do
      let(:filter) { described_class.new(mode: :block) }

      it "raises PIIDetectedError when PII is found" do
        c = content("email: test@example.com")
        expect { filter.filter(c) }.to raise_error(Spurline::PIIDetectedError)
      end

      it "includes the PII types in the error message" do
        c = content("email: test@example.com and SSN: 123-45-6789")
        expect { filter.filter(c) }.to raise_error(
          Spurline::PIIDetectedError,
          /Types found: .*email/
        )
      end

      it "includes trust and source in the error message" do
        c = content("email: test@example.com", trust: :external, source: "tool:search")
        expect { filter.filter(c) }.to raise_error(
          Spurline::PIIDetectedError,
          /trust: external.*source: tool:search/
        )
      end

      it "allows content with no PII" do
        c = content("Just a normal message")
        result = filter.filter(c)
        expect(result).to eq(c)
      end
    end

    context "with :warn mode" do
      let(:filter) { described_class.new(mode: :warn) }

      it "returns content unchanged even when PII is found" do
        c = content("email: test@example.com")
        result = filter.filter(c)
        expect(result).to eq(c)
        expect(result.text).to include("test@example.com")
      end

      it "allows content with no PII" do
        c = content("Just a normal message")
        result = filter.filter(c)
        expect(result).to eq(c)
      end
    end

    context "trust level skipping" do
      let(:filter) { described_class.new(mode: :block) }

      it "skips system trust content" do
        c = content("email: admin@example.com", trust: :system)
        result = filter.filter(c)
        expect(result).to eq(c)
      end

      it "skips operator trust content" do
        c = content("email: admin@example.com", trust: :operator)
        result = filter.filter(c)
        expect(result).to eq(c)
      end

      it "scans user trust content" do
        c = content("email: user@example.com", trust: :user)
        expect { filter.filter(c) }.to raise_error(Spurline::PIIDetectedError)
      end

      it "scans external trust content" do
        c = content("email: user@example.com", trust: :external)
        expect { filter.filter(c) }.to raise_error(Spurline::PIIDetectedError)
      end

      it "scans untrusted content" do
        c = content("email: user@example.com", trust: :untrusted)
        expect { filter.filter(c) }.to raise_error(Spurline::PIIDetectedError)
      end
    end
  end
end
