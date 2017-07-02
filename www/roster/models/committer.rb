class Committer

  def self.serialize(id, env)
    response = {}

    person = ASF::Person.find(id)
    person.reload!
    return unless person.attrs['cn']

    response[:id] = id

    response[:member] = person.asf_member?
    # reformat the timestamp
    m = person.createTimestamp.match(/^(\d\d\d\d)(\d\d)(\d\d)/)
    if m
      response[:createTimestamp] = m[1] + '-' + m[2] + '-' + m[3]
    else # should not happen, but ...
      response[:createTimestamp] = person.createTimestamp
    end

    name = {}

    if person.icla
      name[:public_name] = person.public_name
      name[:legal_name] = person.icla.legal_name
    end

    unless person.attrs['cn'].empty?
      name[:ldap] = person.attrs['cn'].first.force_encoding('utf-8')
    end

    unless person.attrs['givenName'].empty?
      name[:given_name] = person.attrs['givenName'].first.force_encoding('utf-8')
    end

    response[:name] = name

    response[:mail] = person.all_mail

    unless person.pgp_key_fingerprints.empty?
      response[:pgp] = person.pgp_key_fingerprints 
    end

    unless person.ssh_public_keys.empty?
      response[:ssh] = person.ssh_public_keys
    end

    if person.attrs['asf-sascore']
      response[:sascore] = person.attrs['asf-sascore'].first
    end

    if person.attrs['githubUsername']
      response[:githubUsername] = person.githubUsername
    end

    response[:urls] = person.urls unless person.urls.empty?

    response[:committees] = person.committees.map(&:name)

    response[:podlings] = 
      (person.projects.map(&:name) & ASF::Podling.current.map(&:id)).sort

    response[:groups] = person.services
    response[:committer] = []
    committees = ASF::Committee.list.map(&:id)
    person.groups.map(&:name).each do |group|
      if committees.include? group
        unless response[:committees].include? group
          response[:committer] << group 
        end
      else
        response[:groups] << group
      end
    end

    ASF::Authorization.new('asf').each do |group, members|
      response[:groups] << group if members.include? id
    end

    ASF::Authorization.new('pit').each do |group, members|
      response[:groups] << group if members.include? id
    end

    response[:committees].sort!
    response[:groups].sort!
    response[:committer].sort!

    if ASF::Person.find(env.user).asf_member?
      response[:forms] = {}

      if person.icla and person.icla.claRef # Not all people have iclas
        iclas = ASF::SVN['private/documents/iclas']
        claRef = person.icla.claRef.untaint
        if File.exist? File.join(iclas, claRef + '.pdf')
          response[:forms][:icla] = claRef + '.pdf'
        elsif Dir.exist? File.join(iclas, claRef)
          response[:forms][:icla] = claRef + '/'
        end
      end

      member = {}

      if person.asf_member? # TODO is this the correct check? it includes people in members unix group
        member[:info] = person.members_txt
        member[:status] = ASF::Member.status[id] || 'Active'

        if person.icla # not all members have iclas
          apps = ASF::SVN['private/documents/member_apps']
          [
            person.icla.legal_name, 
            person.icla.name,
            # allow for member in LDAP to not be in members.txt (e.g. infra staff)
            (member[:info] or "?\n").split("\n").first.strip
          ].uniq.each do |name|
            next unless name
            memapp = name.downcase.gsub(/\s/, '-').untaint
            if apps and File.exist? File.join(apps, memapp + '.pdf')
              response[:forms][:member] = memapp + '.pdf'
            end
          end
        end
      else
        if person.member_nomination
          member[:nomination] = person.member_nomination
        end
      end

      response[:member] = member unless member.empty?

    end

    if ASF::Person.find(env.user).asf_member? or env.user = id
      response[:moderates] = {}

      require 'whimsy/asf/mlist'
      ASF::MLIST.moderates(person.all_mail, response)
    end

    if env.user == id
      require 'whimsy/asf/mlist'
      ASF::MLIST.subscriptions(person.all_mail, response)
    end

    response
  end
end
