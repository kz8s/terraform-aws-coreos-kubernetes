resource "template_file" "cloud-config" {
  count = "${ length( split(",", var.etcd-ips) ) }"

  template = <<EOF
#cloud-config

---
coreos:

  etcd2:
    advertise-client-urls: http://${ fqdn }:2379
    # cert-file: /etc/etcd/ssl/k8s-etcd.pem
    # debug: true
    discovery-srv: ${ internal-tld }
    initial-advertise-peer-urls: https://${ fqdn }:2380
    initial-cluster-state: new
    initial-cluster-token: ${ cluster-token }
    # key-file: /etc/etcd/ssl/k8s-etcd-key.pem
    listen-client-urls: http://0.0.0.0:2379
    listen-peer-urls: https://0.0.0.0:2380
    name: ${ hostname }
    peer-trusted-ca-file: /etc/etcd/ssl/ca.pem
    peer-client-cert-auth: true
    peer-cert-file: /etc/etcd/ssl/k8s-etcd.pem
    peer-key-file: /etc/etcd/ssl/k8s-etcd-key.pem

  units:
    - name: etcd2.service
      command: start
      drop-ins:
        - name: wait-for-certs.conf
          content: |
            [Unit]
            After=get-ssl.service
            Requires=get-ssl.service

    - name: s3-get-presigned-url.service
      command: start
      content: |
        [Unit]
        After=network-online.target
        Description=Install s3-get-presigned-url
        Requires=network-online.target
        [Service]
        ExecStartPre=-/usr/bin/mkdir -p /opt/bin
        ExecStart=/usr/bin/curl -L -o /opt/bin/s3-get-presigned-url \
          https://github.com/kz8s/s3-get-presigned-url/releases/download/v0.1/s3-get-presigned-url_linux_amd64
        ExecStart=/usr/bin/chmod +x /opt/bin/s3-get-presigned-url
        RemainAfterExit=yes
        Type=oneshot

    - name: get-ssl.service
      command: start
      content: |
        [Unit]
        After=s3-get-presigned-url.service
        Description=Get ssl artifacts from s3 bucket using IAM role
        Requires=s3-get-presigned-url.service
        [Service]
        ExecStartPre=-/usr/bin/mkdir -p /etc/etcd/ssl
        ExecStart=/bin/sh -c "/usr/bin/curl $(/opt/bin/s3-get-presigned-url \
          ${ region } ${ bucket } ${ ssl-tar }) | tar xv -C /etc/etcd/ssl/"
        RemainAfterExit=yes
        Type=oneshot

    - name: get-manifests.service
      command: start
      content: |
        [Unit]
        After=s3-get-presigned-url.service
        Description=Get kubernetes manifest from s3 bucket using IAM role
        Requires=s3-get-presigned-url.service
        [Service]
        ExecStartPre=-/usr/bin/mkdir -p /etc/kubernetes/manifests
        ExecStart=/bin/sh -c "/usr/bin/curl $(/opt/bin/s3-get-presigned-url \
          ${ region } ${ bucket } ${ etc-tar }) | tar xv -C /etc/kubernetes/manifests/"
        RemainAfterExit=yes
        Type=oneshot

  update:
    reboot-strategy: etcd-lock
EOF

  vars {
    bucket = "${ var.bucket-prefix }"
    cluster-token = "etcd-cluster-${ var.name }"
    coreos-hyperkube-image = "${ var.coreos-hyperkube-image }"
    coreos-hyperkube-tag = "${ var.coreos-hyperkube-tag }"
    dns-service-ip = "${ var.dns-service-ip }"
    etc-tar = "/manifests/etc.tar"
    fqdn = "etcd${ count.index + 1 }.${ var.internal-tld }"
    hostname = "etcd${ count.index + 1 }"
    internal-tld = "${ var.internal-tld }"
    log-group = "k8s-${ var.name }"
    pod-ip-range = "${ var.pod-ip-range }"
    region = "${ var.region }"
    service-ip-range = "${ var.service-ip-range }"
    ssl-tar = "ssl/k8s-etcd.tar"
  }
}
