class LabController < ApplicationController
  include ApiHelper

  def ips
    @domain = params['domain']
    @ips = get_ips_of_domain(@domain)
  end

  def domains
    @domain = params['domain']
    ips = get_ips_of_domain(@domain)
    if ips
      all_ips = []
      ips.each do |net|
        ipnet,hosts,ips,netipcnt = net
        all_ips += ips.split(',')
      end

      @sphinxql_sql = ""
      if all_ips.size>0
        @sphinxql_sql = "(@ip \"#{all_ips.join('" | "')}\") @host -#{@domain}"
      end
      @results = search_sphinxql(@sphinxql_sql)
      @domains = @results.map{|r| r.domain}.uniq
    end
  end

  private
  def get_ips_of_domain(domain)
    if domain
      key = 'domain_net:'+domain.downcase
      @ips = Sidekiq.redis{|redis| redis.get(key) }
      if @ips
        @ips = JSON.parse(@ips)
      else
        @ips = Subdomain.connection.execute(%Q{
              select INET_NTOA(INET_ATON(ip) & 0xFFFFFF00) as net,GROUP_CONCAT(hosts) as hosts,GROUP_CONCAT(ip) as ips,count(*) as cnt from(
                select ip,GROUP_CONCAT(host) as hosts from (select ip, host from subdomain
                where reverse_domain=reverse(#{Subdomain.connection.quote(@domain)}) limit 10000) t group by ip
              )t group by net order by cnt desc,net asc
            })
        Sidekiq.redis{|redis|
          redis.set(key, @ips.to_json)
          redis.expire(key, 60*60*24)
        }
      end
      return @ips
    end
    nil
  end
end