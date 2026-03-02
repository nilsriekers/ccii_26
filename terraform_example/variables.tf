variable "project_id" {
  description = "gen-lang-client-0761701245"
  type        = string
}

variable "project_number" {
  description = "149531162483"
  type        = string
}

variable "region" {
  description = "GCP Region (z.B. europe-west1, europe-central2)"
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "GCP Zone (z.B. europe-west1-b, europe-central2-b)"
  type        = string
  default     = "europe-west1-b"
}

variable "vm_name" {
  description = "Name der VM-Instanz"
  type        = string
  default     = "meine-vm"
}

variable "machine_type" {
  description = "Maschinentyp (z.B. g1-small, e2-micro, e2-small)"
  type        = string
  default     = "g1-small"
}

variable "ssh_user" {
  description = "SSH-Benutzername"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key" {
  description = "Euer oeffentlicher SSH-Schluessel (Inhalt von ~/.ssh/id_rsa.pub)"
  type        = string
}
