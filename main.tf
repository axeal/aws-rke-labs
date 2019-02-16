
provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "${var.aws_region}"
}

resource "aws_key_pair" "ssh_key" {
  key_name   = "aws-rke-labs-key"
  public_key = "${file("~/.ssh/id_rsa.pub")}"
}

resource "aws_spot_instance_request" "eks_cluster" {
  count                = "${var.cluster_size}"
  ami                  = "${var.aws_ami}"
  instance_type        = "${var.aws_instance_type}"
  key_name             = "${aws_key_pair.ssh_key.key_name}"
  wait_for_fulfillment = true
  user_data            = "${data.template_file.userdata.rendered}"
}

data "template_file" "userdata" {
  template = "${file("files/userdata.tmpl")}"

  vars {
    docker_version = "${var.docker_version}"
  }
}

data "template_file" "node" {
  template = "${file("files/node.yml.tmpl")}"
  count    = "${var.cluster_size}"
  vars = {
    public_ip  = "${aws_spot_instance_request.eks_cluster.*.public_ip[count.index]}"
    private_ip = "${aws_spot_instance_request.eks_cluster.*.private_ip[count.index]}"
  }
}

data "template_file" "nodes" {
  template = "${file("files/nodes.yml.tmpl")}"
  vars {
    nodes = "${join("",data.template_file.node.*.rendered)}"
  }
}

data "template_file" "curl" {
  template = "curl -fs http://$${public_ip}:8081"
  count    = "${var.cluster_size}"
  vars = {
    public_ip  = "${aws_spot_instance_request.eks_cluster.*.public_ip[count.index]}"
  }
}

data "template_file" "rke" {
  template = "${file("files/rke.sh.tmpl")}"
  vars {
    curl_commands = "${join(" && ",data.template_file.curl.*.rendered)}"
    path_module   = "${path.module}"
  }
}

resource "local_file" "rke-config" {
  content  = "${data.template_file.nodes.rendered}"
  filename = "${path.module}/data/rancher-cluster.yml"
}

resource "local_file" "rke-script" {
  content  = "${data.template_file.rke.rendered}"
  filename = "${path.module}/data/rke.sh"

  provisioner "local-exec" {
    command     = "${path.module}/data/rke.sh"
    working_dir = "${path.module}/data/"
  }
}
