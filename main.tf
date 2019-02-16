
provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "${var.aws_region}"
}

resource "aws_key_pair" "ssh_key" {
  key_name   = "aws-rke-labs-key"
  public_key = "${file("~/.ssh/id_rsa.pub")}"
}

resource "aws_security_group" "eks_cluster" {
  name        = "eks-cluster"
  description = "eks cluster security group"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    self            = true
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

resource "aws_spot_instance_request" "eks_cluster" {
  count                    = "${var.cluster_size}"
  ami                      = "${var.aws_ami}"
  instance_type            = "${var.aws_instance_type}"
  key_name                 = "${aws_key_pair.ssh_key.key_name}"
  wait_for_fulfillment     = true
  user_data                = "${data.template_file.userdata.rendered}"
  availability_zone        = "${var.aws_az}"
  vpc_security_group_ids   = ["${aws_security_group.eks_cluster.id}"]
}

resource "aws_elb" "eks_elb" {
  name               = "eks-elb"
  availability_zones = ["${var.aws_az}"]

  listener {
    instance_port     = 80
    instance_protocol = "tcp"
    lb_port           = 80
    lb_protocol       = "tcp"
  }

  listener {
    instance_port     = 443
    instance_protocol = "tcp"
    lb_port           = 443
    lb_protocol       = "tcp"
  }

  listener {
    instance_port     = 6443
    instance_protocol = "tcp"
    lb_port           = 6443
    lb_protocol       = "tcp"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "TCP:80"
    interval            = 30
  }

  instances = ["${aws_spot_instance_request.eks_cluster.*.spot_instance_id}"]
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
    elb_address = "${aws_elb.eks_elb.dns_name}"
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

  provisioner "local-exec" {
    when    = "destroy"
    command = "rm -f ${path.module}/data/kube_config_rancher-cluster.yml"
  }
}
