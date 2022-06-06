variable "name" {
  default = "phxvlabs-cosign-cicd"
  type    = string
}

variable "image_url_signed" {
  type = string
}

variable "image_url_unsigned" {
  type = string
}