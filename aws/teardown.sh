#!/usr/bin/env bash
# 정리
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REGION="${REGION:-ap-northeast-2}"
[ -f "$HERE/env.sh" ] && source "$HERE/env.sh"
TAG=ace-lt-poc

aws() { command aws --region "$REGION" "$@"; }
say() { echo "[$(date +%H:%M:%S)] $*"; }

say "태그로 인스턴스 조회 (Project=$TAG)"
IDS="$(aws ec2 describe-instances \
	--filters "Name=tag:Project,Values=$TAG" \
		'Name=instance-state-name,Values=pending,running,stopping,stopped' \
	--query 'Reservations[].Instances[].InstanceId' --output text)"

if [ -z "$IDS" ]; then
	say "살아 있는 인스턴스 없음"
else
	aws ec2 describe-instances --instance-ids $IDS \
		--query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,Tags[?Key==`Name`]|[0].Value]' \
		--output table
	read -r -p "위 인스턴스를 terminate 할까요? (yes 입력) " ANS
	[ "$ANS" = "yes" ] || { echo "취소"; exit 1; }
	aws ec2 terminate-instances --instance-ids $IDS >/dev/null
	say "terminate 요청. 완료 대기"
	aws ec2 wait instance-terminated --instance-ids $IDS
	say "terminated"
fi

echo
say "── 고아 리소스 검사 ──"

echo "1) 미연결 EBS 볼륨 (available = 아무 인스턴스에도 안 붙음)"
VOLS="$(aws ec2 describe-volumes --filters Name=status,Values=available \
	--query 'Volumes[].[VolumeId,Size,CreateTime]' --output text)"
if [ -z "$VOLS" ]; then echo "   없음 ✅"; else
	echo "$VOLS" | sed 's/^/   /'
	echo "   → 삭제: aws ec2 delete-volume --region $REGION --volume-id <id>"
fi

echo "2) 미사용 Elastic IP (할당만 하고 안 쓰면 시간당 과금)"
EIPS="$(aws ec2 describe-addresses \
	--query 'Addresses[?AssociationId==null].[PublicIp,AllocationId]' --output text)"
if [ -z "$EIPS" ]; then echo "   없음 ✅"; else
	echo "$EIPS" | sed 's/^/   /'
	echo "   → 릴리스: aws ec2 release-address --region $REGION --allocation-id <id>"
fi

echo "3) 남은 인스턴스 (terminated 는 과금 없음)"
aws ec2 describe-instances --filters "Name=tag:Project,Values=$TAG" \
	--query 'Reservations[].Instances[].[InstanceId,State.Name]' --output text | sed 's/^/   /'

echo
say "보안그룹·키페어는 무료라 남겨도 된다"
say "지우려면: aws ec2 delete-security-group --group-name ${TAG}-{load,app,db}"
say "          aws ec2 delete-key-pair --key-name ace-lt-key"
