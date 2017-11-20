# not tested but should work
# in case of problems https://github.com/jeremylong/InstallCert
# Certificate is needed for owasp dependency check to work, it is intermediatory certificate for let's encrypt
keytool -importcert -alias "DST" -keystore "C:\Program Files (x86)\Jenkins\jre\lib\security\cacerts" -storepass changeit -file .\dst.cer