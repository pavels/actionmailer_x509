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

    def decode(raw_mail)
      x509_crypt = ActionMailerX509::X509.new(
          self.x509[:crypt_cert],
          self.x509[:crypt_key],
          self.x509[:crypt_passphrase],
          self.x509[:crypt_cipher])
      x509_crypt.decode(raw_mail)
    end

  private
    # X509 SMIME signing and\or crypting
    def x509_smime(message)
      if self.x509[:sign_enable] || self.x509[:crypt_enable]
        x509_crypt = ActionMailerX509::X509.new(
            self.x509[:crypt_cert],
            self.x509[:crypt_key],
            self.x509[:crypt_passphrase],
            self.x509[:crypt_cipher])

        x509_sign = ActionMailerX509::X509.new(
            self.x509[:sign_cert],
            self.x509[:sign_key],
            self.x509[:sign_passphrase])

        # NOTE: the one following line is the slowest part of this code, signing is sloooow
        p7 = message.encoded
        p7 = x509_sign.sign(p7) if self.x509[:sign_enable]
        p7 = x509_crypt.encode(p7) if self.x509[:crypt_enable]

        message.body = ''
        create_parts_from_responses(message, [
            {
                body: p7,
                content_disposition: 'attachment; filename="smime.p7m"',
                content_type: 'multipart/mixed'
            }
        ])
      end
      message
    end
  end
end
