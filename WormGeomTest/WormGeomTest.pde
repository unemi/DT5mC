ArrayList<PVector> p = new ArrayList();
void setup() {
  size(800,800);
  p.add(new PVector(100,400));
  p.add(new PVector(400,400));
}
void draw() {
  background(220);
  noStroke();
  fill(64);
  beginShape(TRIANGLE_STRIP);
  int sz = p.size();
  PVector p1 = p.get(0), p2 = p.get(1);
  vxEnd(PVector.sub(p1,PVector.sub(p2,p1)), p1);
  for (int i = 1; i < sz - 1; i ++)
    vxJoint(p.get(i-1),p.get(i),p.get(i+1));
  vxEnd(p.get(sz - 2), p.get(sz - 1));
  endShape();
}
float lineWeight = 5;
float maxDPhi = PI / 8;
float angle(PVector v1, PVector v2) {
  float d = atan2(v1.y, v1.x) - atan2(v2.y, v2.x);
  if (d < -PI) d += TWO_PI;
  else if (d > PI) d -= TWO_PI;
  return d;
}
void vertexV(PVector v) { vertex(v.x, v.y); }
void vxEnd(PVector p1, PVector p2) {
  PVector e = PVector.sub(p2,p1).rotate(PI/2).setMag(lineWeight);
  vertexV(PVector.add(p2,e));
  vertexV(PVector.sub(p2,e));
}
void vxJoint(PVector p1, PVector p2, PVector p3) {
  PVector v1 = PVector.sub(p1,p2), v2 = PVector.sub(p3,p2);
  float d = lineWeight / sin(angle(v1,v2) / 2.0);
  PVector e = PVector.add(
    v1.normalize(), v2.normalize()).setMag(d);
  vertexV(PVector.add(p2,e));
  vertexV(PVector.sub(p2,e));
}
void checkAngle(int idx) {
  PVector p1 = p.get(idx - 1);
  PVector p2 = p.get(idx);
  PVector p3 = p.get(idx + 1);
  float dphi = angle(PVector.sub(p2,p1), PVector.sub(p3,p2));
  if (abs(dphi) > maxDPhi) {
    float d1 = p2.dist(p1), d2 = p2.dist(p3);
    float s = min(d1, d2) / 3;
    p.add(idx + 1, PVector.add(p2, PVector.sub(p3,p2).div(d2).mult(s)));
    p2.add(PVector.sub(p1,p2).div(d1).mult(s));
    checkAngle(idx + 1);
    checkAngle(idx);
  }
}
void mousePressed() {
  p.add(new PVector(mouseX,mouseY));
  checkAngle(p.size() - 2);
}
