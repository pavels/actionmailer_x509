# Copyright (c) 2007 Fabien Penso <fabien.penso@conovae.com>
#
# actionmailer_x509 is a rails plugin to allow X509 outgoing mail to be X509
# signed.
#
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the University of California, Berkeley nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE REGENTS AND CONTRIBUTORS BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
require 'actionmailer_x509/railtie' if defined?(Rails)
require 'actionmailer_x509/x509'
require 'openssl'

module ActionMailer #:nodoc:
  class Base #:nodoc:
    class_attribute :x509
    self.x509 = {
      sign_enable: true,
      sign_cert: 'certs/server.crt',
      sign_key: 'certs/server.key',
      sign_passphrase: 'hisp',
      crypt_enable: true,
      crypt_cert: 'certs/ca.crt',
      crypt_key: 'certs/ca.key',
      crypt_passphrase: 'hisp',
      crypt_cipher: 'des'
    }

    alias_method :old_mail, :mail

    def mail(headers = {}, &block)
      message = old_mail(headers, &block)
      x509_smime(message)
    end


    def self.get_crypter
      ActionMailerX509::X509.new(
          self.x509[:crypt_cert],
          self.x509[:crypt_key],
          self.x509[:crypt_passphrase],
          self.x509[:crypt_cipher])
    end

    def self.get_signer
      ActionMailerX509::X509.new(
          self.x509[:sign_cert],
          self.x509[:sign_key],
          self.x509[:sign_passphrase])
    end

    def self.proceed(mail, x509_settings={})
      x509.reverse_merge!(x509_settings)

      if mail.is_a? String
        get_crypter.decode(mail)
      elsif mail.is_a? Mail::Message
        if mail.multipart?
          if mail.parts.first.body.to_s == 'This is an S/MIME signed message'
            sign = mail.parts.select { |p| p.content_type == 'application/x-pkcs7-signature'}
            raise Exception.new 'Sign attach not finded'
            get_signer.verify(sign.first.body)
          end
        else
          get_crypter.decode(mail.body.to_s)
        end
      end || mail.body.to_s
    end

  private
    # X509 SMIME signing and\or crypting
    def x509_smime(message)
      if self.x509[:sign_enable] || self.x509[:crypt_enable]
        @signed = get_signer.sign(message.body.to_s) if self.x509[:sign_enable] #message.encoded
        @coded = get_crypter.encode(@signed || message.body.to_s) if self.x509[:crypt_enable]

        Mail::Header

        p = Mail.new(@coded || @signed)
        p.header.fields.each {|field| (message.header[field.name] = field.value)}

        if @coded
          message.header["Content-Transfer-Encoding"] = 'base64'
          message.instance_variable_set :@body_raw, Base64.encode64(p.body.to_s)
        else
          message.body = p.body.to_s
        end
      end
      message
    end

    def get_crypter
      ActionMailerX509::X509.new(
          self.x509[:crypt_cert],
          self.x509[:crypt_key],
          self.x509[:crypt_passphrase],
          self.x509[:crypt_cipher])
    end

    def get_signer
      ActionMailerX509::X509.new(
          self.x509[:sign_cert],
          self.x509[:sign_key],
          self.x509[:sign_passphrase])
    end
  end
end
