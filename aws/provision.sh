#!/usr/bin/env bash
# AWS 프로비저닝
# 4대 (db / app1 / app2 / load)
set -euo pipefail

REGION="${REGION:-ap-northeast-2}"
TAG=ace-lt-poc
KEY_NAME=ace-lt-key
KEY_FILE="$(cd "$(dirname "$0")" && pwd)/ace-lt.pem"
ENV_FILE="$(cd "$(dirname "$0")" && pwd)/env.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"

# c5 = 고정 성능. t3 는 버스터블이라 CPU 크레딧이 소진되면 스로틀링돼 측정을 조용히 망친다
TYPE_DB=c5.large
TYPE_APP=c5.large
TYPE_LOAD=c5.xlarge
HOURLY=0.48

aws() { command aws --region "$REGION" "$@"; }
say() { echo "[$(date +%H:%M:%S)] $*"; }

# ── 0. 사전 확인 ──
say "자격증명 확인"
aws sts get-caller-identity --query '[Account,Arn]' --output text

MY_IP="$(curl -s --max-time 5 https://checkip.amazonaws.com | tr -d '\n')"
[ -n "$MY_IP" ] || { echo "공인 IP 확인 실패"; exit 1; }
say "SSH 허용 IP: ${MY_IP}/32"

AMI="$(aws ssm get-parameters \
	--names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
	--query 'Parameters[0].Value' --output text 2>/dev/null || true)"
if [ -z "$AMI" ] || [ "$AMI" = "None" ]; then
	# ssm 권한이 없으면 describe-images 로 (EC2FullAccess 만 있는 경우)
	AMI="$(aws ec2 describe-images --owners amazon \
		--filters 'Name=name,Values=al2023-ami-2023.*-kernel-6.1-x86_64' 'Name=state,Values=available' \
		--query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)"
fi
say "AMI: $AMI"

VPC="$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)"
# 같은 AZ 강제. 다른 AZ 면 지연이 섞이고 전송비가 붙는다
read -r SUBNET AZ <<<"$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC" \
	--query 'Subnets[0].[SubnetId,AvailabilityZone]' --output text)"
say "VPC $VPC / Subnet $SUBNET / AZ $AZ"

# ── 승인 게이트 ──
cat <<EOF

────────────────────────────────────────────────
 생성할 리소스        리전 $REGION / AZ $AZ
────────────────────────────────────────────────
  db     $TYPE_DB     MySQL 8.4 + Redis 8.2
  app1   $TYPE_APP    java -jar
  app2   $TYPE_APP    java -jar
  load   $TYPE_LOAD   k6
  보안그룹 3개 (SSH 는 ${MY_IP}/32 만)
  키페어 $KEY_NAME → $KEY_FILE

 예상 요금  시간당 약 \$${HOURLY}
            45분 ≈ \$0.36 (약 500원) / 1시간 ≈ \$0.48
            방치 하루 ≈ \$11.5 (약 16,000원)

 전 인스턴스에 shutdown -h +240 이 걸린다 (stop 이지 terminate 아님).
 측정 후 반드시 ./aws/teardown.sh
────────────────────────────────────────────────
EOF
read -r -p "생성할까요? (yes 입력) " ANS
[ "$ANS" = "yes" ] || { echo "취소"; exit 1; }

# ── 1. 키페어 ──
if [ -f "$KEY_FILE" ]; then
	say "키페어 파일이 이미 있다: $KEY_FILE (재사용)"
else
	aws ec2 delete-key-pair --key-name "$KEY_NAME" >/dev/null 2>&1 || true
	aws ec2 create-key-pair --key-name "$KEY_NAME" \
		--query KeyMaterial --output text > "$KEY_FILE"
	chmod 400 "$KEY_FILE"
	say "키페어 생성 → $KEY_FILE"
fi

# ── 2. 보안그룹 3개. 서로를 참조하므로 순서가 정해진다 ──
sg() {  # sg <이름> <설명>
	local id
	id="$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$1" \
		--query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo None)"
	if [ "$id" = "None" ] || [ -z "$id" ]; then
		id="$(aws ec2 create-security-group --group-name "$1" --description "$2" \
			--vpc-id "$VPC" --query GroupId --output text)"
	fi
	echo "$id"
}

SG_LOAD="$(sg "${TAG}-load" 'ace-lt load generator')"
SG_APP="$(sg "${TAG}-app" 'ace-lt app')"
SG_DB="$(sg "${TAG}-db" 'ace-lt db')"
say "SG  load $SG_LOAD / app $SG_APP / db $SG_DB"

allow() {  # allow <sg> <port> <source>  — 중복은 무시
	if [[ "$3" == sg-* ]]; then
		aws ec2 authorize-security-group-ingress --group-id "$1" \
			--protocol tcp --port "$2" --source-group "$3" >/dev/null 2>&1 || true
	else
		aws ec2 authorize-security-group-ingress --group-id "$1" \
			--protocol tcp --port "$2" --cidr "$3" >/dev/null 2>&1 || true
	fi
}

# SSH 는 내 IP 만. 0.0.0.0/0 을 쓰지 않는다
for S in "$SG_LOAD" "$SG_APP" "$SG_DB"; do allow "$S" 22 "${MY_IP}/32"; done
# /reset 에 인증이 없다. 인터넷에 열면 누구나 재고를 조작할 수 있다
allow "$SG_APP" 8080-8083 "$SG_LOAD"
allow "$SG_APP" 8080-8083 "$SG_APP"      # app 끼리 (축 7 에서 서로 폴링할 여지)
allow "$SG_DB" 3306 "$SG_APP"
allow "$SG_DB" 6379 "$SG_APP"
say "인바운드 설정 완료 (앱 포트는 sg-load 에서만, DB 는 sg-app 에서만)"

# ── 3. 인스턴스 ──
launch() {  # launch <이름> <타입> <sg> <user-data> [추가 env]
	aws ec2 run-instances \
		--image-id "$AMI" --instance-type "$2" --key-name "$KEY_NAME" \
		--security-group-ids "$3" --subnet-id "$SUBNET" \
		--user-data "file://$4" \
		--tag-specifications \
			"ResourceType=instance,Tags=[{Key=Name,Value=${TAG}-$1},{Key=Project,Value=${TAG}}]" \
		--query 'Instances[0].InstanceId' --output text
}

say "db 기동"
ID_DB="$(launch db "$TYPE_DB" "$SG_DB" "$HERE/user-data-db.sh")"
say "app1 기동"
ID_APP1="$(launch app1 "$TYPE_APP" "$SG_APP" "$HERE/user-data-app.sh")"
say "app2 기동"
ID_APP2="$(launch app2 "$TYPE_APP" "$SG_APP" "$HERE/user-data-app.sh")"
say "load 기동"
ID_LOAD="$(launch load "$TYPE_LOAD" "$SG_LOAD" "$HERE/user-data-load.sh")"

say "running 대기"
aws ec2 wait instance-running --instance-ids "$ID_DB" "$ID_APP1" "$ID_APP2" "$ID_LOAD"

ip() { aws ec2 describe-instances --instance-ids "$1" \
	--query "Reservations[0].Instances[0].$2" --output text; }

cat > "$ENV_FILE" <<EOF
# provision.sh 생성. git 추적 안 됨
export REGION=$REGION
export KEY_FILE=$KEY_FILE
export ID_DB=$ID_DB ID_APP1=$ID_APP1 ID_APP2=$ID_APP2 ID_LOAD=$ID_LOAD
export DB_PRIV=$(ip "$ID_DB" PrivateIpAddress)
export APP1_IP=$(ip "$ID_APP1" PublicIpAddress)
export APP1_PRIV=$(ip "$ID_APP1" PrivateIpAddress)
export APP2_IP=$(ip "$ID_APP2" PublicIpAddress)
export APP2_PRIV=$(ip "$ID_APP2" PrivateIpAddress)
export LOAD_IP=$(ip "$ID_LOAD" PublicIpAddress)
EOF

say "완료. aws/env.sh 기록"
cat "$ENV_FILE"
echo
echo "다음: ./aws/deploy.sh   (user-data 설치가 끝날 때까지 1~2분 기다린다)"
