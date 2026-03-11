# frozen_string_literal: true

require "fileutils"
require "openssl"
require "securerandom"
require "shellwords"
require "tempfile"
require "yaml"

module Spurline
  module CLI
    class Credentials
      DEFAULT_TEMPLATE = <<~YAML
        # Spurline credentials - encrypted at rest.
        # Edit with: spur credentials:edit
        #
        anthropic_api_key: ""
        # brave_api_key: ""
      YAML

      IV_BYTES = 12
      AUTH_TAG_BYTES = 16
      KEY_BYTES = 32

      def initialize(project_root:)
        @project_root = File.expand_path(project_root)
      end

      def edit!
        ensure_master_key!
        plaintext = File.file?(credentials_path) ? decrypt_existing_credentials : project_template

        Tempfile.create(["spurline-credentials", ".yml"]) do |file|
          path = file.path
          File.write(path, plaintext)
          open_editor!(file.path)
          edited = File.read(path)
          parse_yaml(edited)
          encrypt_and_write(edited)
        end
      end

      def read
        return {} unless File.file?(credentials_path)

        parse_yaml(decrypt_existing_credentials)
      end

      def master_key
        @master_key ||= resolve_master_key
      end

      private

      attr_reader :project_root

      def project_template
        template_path = File.join(project_root, "config", "credentials.template.yml")
        File.file?(template_path) ? File.read(template_path) : DEFAULT_TEMPLATE
      end

      def credentials_path
        File.join(project_root, "config", "credentials.enc.yml")
      end

      def master_key_path
        File.join(project_root, "config", "master.key")
      end

      def ensure_master_key!
        return if master_key

        generate_master_key!
        @master_key = resolve_master_key
      end

      def generate_master_key!
        FileUtils.mkdir_p(File.dirname(master_key_path))
        hex_key = SecureRandom.random_bytes(KEY_BYTES).unpack1("H*")
        File.write(master_key_path, "#{hex_key}\n")
        File.chmod(0o600, master_key_path)
      end

      def resolve_master_key
        hex = ENV.fetch("SPURLINE_MASTER_KEY", nil)
        hex = read_master_key_file if hex.nil? || hex.strip.empty?
        return nil if hex.nil? || hex.strip.empty?

        decode_hex_key(hex)
      end

      def read_master_key_file
        return nil unless File.file?(master_key_path)

        File.read(master_key_path)
      end

      def decode_hex_key(hex)
        stripped = hex.to_s.strip
        unless stripped.match?(/\A[0-9a-fA-F]{#{KEY_BYTES * 2}}\z/)
          raise Spurline::CredentialsMissingKeyError,
            "Master key must be #{KEY_BYTES * 2} hex characters"
        end

        [stripped].pack("H*")
      end

      def decrypt_existing_credentials
        key = master_key
        unless key
          raise Spurline::CredentialsMissingKeyError,
            "Missing master key. Set SPURLINE_MASTER_KEY or create config/master.key"
        end

        payload = File.binread(credentials_path)
        decrypt(payload, key)
      end

      def encrypt_and_write(plaintext)
        key = master_key
        unless key
          raise Spurline::CredentialsMissingKeyError,
            "Missing master key. Set SPURLINE_MASTER_KEY or create config/master.key"
        end

        payload = encrypt(plaintext, key)
        FileUtils.mkdir_p(File.dirname(credentials_path))
        File.binwrite(credentials_path, payload)
      end

      def encrypt(plaintext, key)
        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.encrypt
        cipher.key = key
        iv = SecureRandom.random_bytes(IV_BYTES)
        cipher.iv = iv
        ciphertext = cipher.update(plaintext) + cipher.final
        tag = cipher.auth_tag
        iv + tag + ciphertext
      end

      def decrypt(payload, key)
        unless payload && payload.bytesize >= (IV_BYTES + AUTH_TAG_BYTES)
          raise Spurline::CredentialsDecryptionError, "Encrypted credentials file is invalid"
        end

        iv = payload.byteslice(0, IV_BYTES)
        tag = payload.byteslice(IV_BYTES, AUTH_TAG_BYTES)
        ciphertext = payload.byteslice(IV_BYTES + AUTH_TAG_BYTES, payload.bytesize)

        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.decrypt
        cipher.key = key
        cipher.iv = iv
        cipher.auth_tag = tag
        cipher.update(ciphertext) + cipher.final
      rescue OpenSSL::Cipher::CipherError
        raise Spurline::CredentialsDecryptionError, "Could not decrypt credentials with provided master key"
      end

      def open_editor!(path)
        editor = ENV.fetch("EDITOR", "vi")
        command = Shellwords.split(editor)
        ok = system(*command, path)
        return if ok

        raise Spurline::ConfigurationError, "EDITOR command failed: #{editor}"
      end

      def parse_yaml(content)
        parsed = YAML.safe_load(content, aliases: false)
        return {} if parsed.nil?
        return parsed.transform_keys(&:to_s) if parsed.is_a?(Hash)

        raise Spurline::ConfigurationError, "Credentials YAML must contain a mapping"
      rescue Psych::SyntaxError => e
        raise Spurline::ConfigurationError, "Invalid credentials YAML: #{e.message}"
      end
    end
  end
end
