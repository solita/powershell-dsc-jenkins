import jenkins.model.*
import hudson.security.*
import org.jenkinsci.main.modules.cli.auth.ssh.UserPropertyImpl

def solita_jenkins_security_realm = 'jenkins'
def solita_jenkins_username = 'REPLACE_jenkinsusername_REPLACE'
def solita_jenkins_password = 'REPLACE_jenkinspassword_REPLACE'

def jenkins = Jenkins.getInstance()

if (solita_jenkins_security_realm == 'jenkins') {
    if (!(jenkins.getSecurityRealm() instanceof HudsonPrivateSecurityRealm)) {
        jenkins.setSecurityRealm(new HudsonPrivateSecurityRealm(false))
    }

	if (!(jenkins.getAuthorizationStrategy() instanceof FullControlOnceLoggedInAuthorizationStrategy)) {
        jenkins.setAuthorizationStrategy(new FullControlOnceLoggedInAuthorizationStrategy())
    }

    def currentUsers = jenkins.getSecurityRealm().getAllUsers().collect { it.getId() }

    if (!(solita_jenkins_username in currentUsers)) {
        def user = jenkins.getSecurityRealm().createAccount(solita_jenkins_username, solita_jenkins_password)
        user.save()
    }
} else if (solita_jenkins_security_realm == 'none') {
    // If we leave the user, further attempts to use jenkins-cli.jar with
    // key-based authentication enabled fail for some reason. Clearing the
    // user's SSH key wasn't enough to solve the problem.
    solita_jenkins_user = jenkins.getUser(solita_jenkins_username)
    if (solita_jenkins_user) {
        solita_jenkins_user.delete()
    }
    jenkins.disableSecurity()
}
jenkins.save()