function main {
	for i in $(cat /etc/liferay/lxc/dxp-metadata/com.liferay.lxc.dxp.domains 2>/dev/null)
	do
		local url="https://${i}"

		cat >> /etc/caddy.d/liferay_caddy_file << EOF
@origin${url} header Origin ${url}
header @origin${url} Access-Control-Allow-Origin "${url}"
header @origin${url} Vary Origin
EOF
	done

	caddy run --adapter caddyfile --config /etc/caddy/Caddyfile
}

main