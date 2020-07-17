provider "aws"{
  region ="ap-south-1"
}
resource "aws_vpc" "ownvpc" {
  cidr_block       = "192.168.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "myownvpc"
  }
}
resource "aws_subnet" "main3" {
  vpc_id     = "${aws_vpc.ownvpc.id}"
  cidr_block = "192.168.0.0/24"
  availability_zone="ap-south-1a"
  map_public_ip_on_launch=true

  tags = {
    Name = "subnet1"
  }
}
resource "aws_internet_gateway" "gateway1" {
  vpc_id = "${aws_vpc.ownvpc.id}"

  tags = {
    Name = "ig"
  }
}
resource "aws_route_table" "route1" {
  vpc_id = "${aws_vpc.ownvpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gateway1.id}"
  }
 tags = {
    Name = "myroutetb"
  }
}
resource "aws_route_table_association""associate"{
  subnet_id=aws_subnet.main3.id
  route_table_id=aws_route_table.route1.id
}
resource "aws_s3_bucket" "b" {
  acl    = "public-read"

  tags = {
    Name        = "My bucket"
  }
}
resource "aws_s3_bucket_object""object"{
 bucket=aws_s3_bucket.b.id
 key   ="images.png"
}
locals{
 s3_origin_id ="aws_s3_bucket.b.id"
 depends_on=[aws_s3_bucket.b]
}
resource "aws_security_group" "s1" {
  name        = "mysgroup1"
  description = "Allow NFS"
  vpc_id      = "${aws_vpc.ownvpc.id}"

  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "NFSecuritygroup"
  }
}
resource "aws_efs_file_system" "efs" {
  creation_token = "myefs"
  performance_mode="generalPurpose"

  tags = {
    Name = "Myefs"
  }
}
resource "aws_efs_mount_target" "efs-mount" {
  file_system_id = "${aws_efs_file_system.efs.id}"
  subnet_id      = "${aws_subnet.main3.id}"
  security_groups =[aws_security_group.s1.id]
}
resource "aws_instance" "webserver" {
  depends_on = [ aws_efs_mount_target.efs-mount ]
  ami = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = "mykey"
  subnet_id = aws_subnet.main3.id
  vpc_security_group_ids = [ aws_security_group.s1.id ]
  
  tags = {
    Name = "instance1"
  }
}
resource "null_resource" "nullremote1" {
  depends_on = [
    aws_instance.webserver
  ]
  connection {
    type = "ssh"
    user= "ec2-user"
    private_key = file("mykey.pem")
    host = aws_instance.webserver.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git amazon-efs-utils nfs-utils -y",
      "sudo setenforce 0",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd",
      "sudo mount -t efs ${aws_efs_file_system.efs.id}:/ /var/www/html",
      "sudo echo '${aws_efs_file_system.efs.id}:/ /var/www/html efs defaults,_netdev 0 0' >> /etc/fstab",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/mamatha67/efs /var/www/html/"
    ]
  }
}
