//! Tests of the outlines of a page cut in the order of its file: what a
//! filled element drawn later hides, exactly, and nothing else; the joins and
//! the short pieces; the outlines of ellipses; the same bits every time; and
//! every page, checked against a sampling of its elements made apart from
//! this module.
use super::*;

const HEAD: &str =
    r#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 800"><title>Essai</title>"#;

/// A page of these elements, read as the compiled pages are.
fn page(elements: &[String]) -> Page {
    let svg = format!("{HEAD}{}</svg>", elements.concat());
    read_page(&svg).unwrap_or_else(|why| panic!("{why}: {svg}"))
}

fn paint(filled: bool) -> String {
    let fill = if filled { "#ffffff" } else { "none" };
    format!(r##"fill="{fill}" stroke="#2f3d4a" stroke-width="6""##)
}

fn circle(cx: f32, cy: f32, r: f32, filled: bool) -> String {
    format!(r#"<circle cx="{cx}" cy="{cy}" r="{r}" {}/>"#, paint(filled))
}

fn rect(x: f32, y: f32, width: f32, height: f32, filled: bool) -> String {
    format!(
        r#"<rect x="{x}" y="{y}" width="{width}" height="{height}" {}/>"#,
        paint(filled)
    )
}

fn line(x1: f32, y1: f32, x2: f32, y2: f32) -> String {
    format!(
        r#"<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" {}/>"#,
        paint(false)
    )
}

fn path(d: &str, filled: bool) -> String {
    format!(r#"<path d="{d}" {}/>"#, paint(filled))
}

fn ep(x: f32, y: f32) -> EpPoint {
    EpPoint { x, y }
}

fn room() -> Room {
    Room {
        objects: MAX_STROKES,
        points: MAX_TOTAL_POINTS,
    }
}

/// The lines that element `index` of these objects gives. They depend on
/// that element and the ones after it only: they are the lines of the
/// objects from `index` on, less those of the objects after it.
fn lines_of(objects: &[PageObject], index: usize) -> Vec<PageObject> {
    let mut lines = clip_outlines(&objects[index..], room()).unwrap();
    let after = clip_outlines(&objects[index + 1..], room()).unwrap();
    lines.truncate(lines.len() - after.len());
    lines
}

/// Whether element `index` of a page gives its own outline, uncut.
fn whole(page: &Page, index: usize) -> bool {
    let object = &page.objects[index];
    let lines = lines_of(&page.objects, index);
    let style = EpObjectStyle {
        kind: object.style.kind,
        fill_enabled: 0,
        fill_rgb: 0,
    };
    lines.len() == 1
        && lines[0].style == style
        && (lines[0].rgb, lines[0].width) == (object.rgb, object.width)
        && lines[0].points == object.points
}

/// The pieces that element `index` of a page is cut into: freehand lines
/// with its colour and width.
fn pieces(page: &Page, index: usize) -> Vec<Vec<EpPoint>> {
    let object = &page.objects[index];
    lines_of(&page.objects, index)
        .into_iter()
        .map(|line| {
            assert_eq!(line.style, FREEHAND_STYLE);
            assert_eq!((line.rgb, line.width), (object.rgb, object.width));
            line.points
        })
        .collect()
}

fn points64(points: &[EpPoint]) -> Vec<Point> {
    points.iter().map(point).collect()
}

/// The bits of points, added: a pin on every one of them.
fn bits(points: impl IntoIterator<Item = Point>) -> u64 {
    points
        .into_iter()
        .map(|p| u64::from((p[0] as f32).to_bits()) + u64::from((p[1] as f32).to_bits()))
        .sum()
}

fn close(a: EpPoint, b: (f64, f64), tolerance: f64) -> bool {
    (f64::from(a.x) - b.0).abs() <= tolerance && (f64::from(a.y) - b.1).abs() <= tolerance
}

// The checks below share nothing with the module but its types: the box of
// points, the point at `t` of a segment and the distance to a segment are
// written here again.
fn corners_of(points: &[Point]) -> (Point, Point) {
    let fold = |axis: usize, pick: fn(f64, f64) -> f64, start: f64| {
        points.iter().map(|p| p[axis]).fold(start, pick)
    };
    (
        [fold(0, f64::min, f64::MAX), fold(1, f64::min, f64::MAX)],
        [fold(0, f64::max, f64::MIN), fold(1, f64::max, f64::MIN)],
    )
}

fn along(a: Point, b: Point, t: f64) -> Point {
    [a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])]
}

fn segment_distance(p: Point, a: Point, b: Point) -> f64 {
    let d = [b[0] - a[0], b[1] - a[1]];
    let squared = d[0] * d[0] + d[1] * d[1];
    let t = if squared == 0.0 {
        0.0
    } else {
        (((p[0] - a[0]) * d[0] + (p[1] - a[1]) * d[1]) / squared).clamp(0.0, 1.0)
    };
    (a[0] + t * d[0] - p[0]).hypot(a[1] + t * d[1] - p[1])
}

/// How deep `p` lies inside filled element `object`, negative outside: never
/// less than the signed distance to its boundary. The angles around a
/// contour are summed, an ellipse is scaled.
fn depth(object: &PageObject, p: Point) -> f64 {
    let points = points64(&object.points);
    match object.style.kind {
        2 => {
            let (low, high) = corners_of(&points);
            (p[0] - low[0])
                .min(high[0] - p[0])
                .min(p[1] - low[1])
                .min(high[1] - p[1])
        }
        3 => {
            let (low, high) = corners_of(&points);
            let radius = [(high[0] - low[0]) / 2.0, (high[1] - low[1]) / 2.0];
            let u = (p[0] - (low[0] + radius[0])) / radius[0];
            let v = (p[1] - (low[1] + radius[1])) / radius[1];
            let scale = u.hypot(v);
            // Inside, the boundary is at most this far along the ray from
            // the centre; outside, at least this far away.
            (1.0 - scale)
                * if scale <= 1.0 {
                    radius[0].max(radius[1])
                } else {
                    radius[0].min(radius[1])
                }
        }
        _ => {
            let mut angle = 0.0;
            let mut nearest = f64::INFINITY;
            for (index, &a) in points.iter().enumerate() {
                let b = points[(index + 1) % points.len()];
                let (ax, ay, bx, by) = (a[0] - p[0], a[1] - p[1], b[0] - p[0], b[1] - p[1]);
                angle += (ax * by - ay * bx).atan2(ax * bx + ay * by);
                nearest = nearest.min(segment_distance(p, a, b));
            }
            if (angle / TAU).round() != 0.0 {
                nearest
            } else {
                -nearest
            }
        }
    }
}

/// Points along a polyline, `per_unit` to a unit of its length.
fn sampled(corners: &[Point], closed: bool, per_unit: f64) -> Vec<Point> {
    let mut out = vec![corners[0]];
    let segments = corners.len() - usize::from(!closed);
    for index in 0..segments {
        let (a, b) = (corners[index], corners[(index + 1) % corners.len()]);
        let steps = (per_unit * (a[0] - b[0]).hypot(a[1] - b[1]))
            .ceil()
            .max(1.0) as usize;
        out.extend((1..=steps).map(|step| along(a, b, step as f64 / steps as f64)));
    }
    out
}

/// Points along the outline that the file strokes for `object`, about one
/// unit apart, the ellipses with the sine and cosine of the system.
fn samples(object: &PageObject) -> Vec<Point> {
    let points = points64(&object.points);
    let (low, high) = corners_of(&points);
    match object.style.kind {
        2 => sampled(
            &[low, [high[0], low[1]], high, [low[0], high[1]]],
            true,
            1.0,
        ),
        3 => {
            let radius = [(high[0] - low[0]) / 2.0, (high[1] - low[1]) / 2.0];
            let count = (TAU * radius[0].max(radius[1])).ceil() as usize;
            let ellipse: Vec<Point> = (0..count)
                .map(|step| {
                    let angle = TAU * step as f64 / count as f64;
                    [
                        low[0] + radius[0] * (1.0 + angle.cos()),
                        low[1] + radius[1] * (1.0 + angle.sin()),
                    ]
                })
                .collect();
            sampled(&ellipse, true, 1.0)
        }
        KIND_CONTOUR => sampled(&points, true, 1.0),
        _ => sampled(&points, false, 1.0),
    }
}

/// Points along a piece, about a quarter of a unit apart.
fn samples_of_line(points: &[EpPoint]) -> Vec<Point> {
    sampled(&points64(points), false, 4.0)
}

#[test]
fn a_lower_circle_loses_exactly_the_arc_a_later_circle_covers() {
    let page = page(&[
        circle(300.0, 300.0, 100.0, true),
        circle(400.0, 300.0, 100.0, true),
    ]);
    // The later circle is drawn whole, as the file draws it.
    assert!(whole(&page, 1));
    let cut = pieces(&page, 0);
    assert_eq!(cut.len(), 1, "one arc");
    let arc = points64(&cut[0]);
    // It ends where the circles cross, x = 350 and y = 300 ± 50√3, give or
    // take the chords of the outline, two thirds of a turn from its start.
    let crossing = 50.0 * 3f64.sqrt();
    assert!(close(cut[0][0], (350.0, 300.0 + crossing), 0.02));
    assert!(close(
        cut[0][arc.len() - 1],
        (350.0, 300.0 - crossing),
        0.02
    ));
    let two_thirds = 2.0 * TAU * 100.0 / 3.0;
    assert!((length(&arc) - two_thirds).abs() < 0.05, "{}", length(&arc));
    // Between its ends, exactly the points of the outline outside the later
    // circle, in their order; none of those inside it.
    let outline = ellipse_outline([200.0, 200.0], [400.0, 400.0]);
    let outside: Vec<Point> = outline
        .iter()
        .copied()
        .filter(|p| (p[0] - 400.0).hypot(p[1] - 300.0) > 100.0)
        .collect();
    assert_eq!(outside.len(), 141);
    assert_eq!(arc[1..arc.len() - 1], outside);
    // The same bits as a reference made apart, in Python.
    assert_eq!(arc.len(), 143);
    assert_eq!(
        (cut[0][0], cut[0][142]),
        (ep(349.9902, 386.5969), ep(349.9902, 213.4031))
    );
    assert_eq!(bits(arc), 323_941_651_825);

    // Drawn the other way round, the right circle loses its left arc. What
    // is left runs across the start of its outline, its rightmost point:
    // the parts before and after the start make one piece.
    let page = self::page(&[
        circle(400.0, 300.0, 100.0, true),
        circle(300.0, 300.0, 100.0, true),
    ]);
    assert!(whole(&page, 1));
    let cut = pieces(&page, 0);
    assert_eq!(cut.len(), 1, "one arc, joined at the start of the outline");
    let arc = points64(&cut[0]);
    assert!(arc.contains(&[500.0, 300.0]));
    assert!(close(cut[0][0], (350.0, 300.0 - crossing), 0.02));
    assert!(close(
        cut[0][arc.len() - 1],
        (350.0, 300.0 + crossing),
        0.02
    ));
    assert!((length(&arc) - two_thirds).abs() < 0.05, "{}", length(&arc));
    assert_eq!(arc.len(), 143);
    assert_eq!(
        (cut[0][0], cut[0][142]),
        (ep(350.0098, 213.4031), ep(350.0098, 386.5969))
    );
    assert_eq!(bits(arc), 324_877_853_635);

    // A later circle without a fill hides nothing.
    let page = self::page(&[
        circle(300.0, 300.0, 100.0, true),
        circle(400.0, 300.0, 100.0, false),
    ]);
    assert!(whole(&page, 0) && whole(&page, 1));
}

#[test]
fn a_detail_under_a_later_filled_shape_is_cut_where_it_enters_it() {
    let page = page(&[
        // 0: a line through a later rectangle.
        line(100.0, 500.0, 500.0, 500.0),
        // 1: a polyline wholly inside it.
        r##"<polyline points="220,450 280,450 280,550" fill="none" stroke="#2f3d4a" stroke-width="4"/>"##.to_owned(),
        // 2: a curve through a later ellipse.
        path("M600 600 C700 500 900 500 1000 600", false),
        rect(200.0, 400.0, 100.0, 200.0, true),
        // 4: a line drawn after the rectangle, over it.
        line(150.0, 550.0, 350.0, 550.0),
        r##"<ellipse cx="800" cy="560" rx="80" ry="40" fill="#ffffff" stroke="#2f3d4a" stroke-width="6"/>"##.to_owned(),
        // 6: a line under a later outline without a fill.
        line(700.0, 300.0, 900.0, 300.0),
        rect(750.0, 250.0, 100.0, 100.0, false),
    ]);
    // The line keeps what lies outside the rectangle, to its sides exactly.
    assert_eq!(
        pieces(&page, 0),
        [
            vec![ep(100.0, 500.0), ep(200.0, 500.0)],
            vec![ep(300.0, 500.0), ep(500.0, 500.0)]
        ]
    );
    // The polyline is hidden whole: no line at all.
    assert!(lines_of(&page.objects, 1).is_empty());
    // The curve goes on to the edge of the ellipse on both sides, and none
    // of what is left lies inside it.
    let curve = pieces(&page, 2);
    assert_eq!(curve.len(), 2);
    let ellipse = &page.objects[5];
    for end in [curve[0].last().unwrap(), &curve[1][0]] {
        let p = point(end);
        let (u, v) = ((p[0] - 800.0) / 80.0, (p[1] - 560.0) / 40.0);
        assert!((u * u + v * v - 1.0).abs() < 1e-5, "{end:?}");
    }
    assert_eq!(curve[0][0], page.objects[2].points[0]);
    assert_eq!(curve[1].last(), page.objects[2].points.last());
    for piece in &curve {
        for p in samples_of_line(piece) {
            assert!(depth(ellipse, p) <= 1e-3, "{p:?}");
        }
    }
    // Drawn over the shapes, or under shapes without a fill: whole.
    for index in [3, 4, 5, 6, 7] {
        assert!(whole(&page, index), "{index}");
    }
}

#[test]
fn nothing_is_cut_where_nothing_filled_is_drawn_later_or_shapes_only_touch() {
    let page = page(&[
        // 0, 1: rectangles side by side, sharing a side.
        rect(100.0, 100.0, 100.0, 100.0, true),
        rect(200.0, 100.0, 100.0, 100.0, true),
        // 2: a line through the corner of a later rectangle, 3.
        line(100.0, 500.0, 300.0, 700.0),
        rect(200.0, 400.0, 200.0, 200.0, true),
        // 4: a line along a side of a later contour, 5, outside the rest.
        line(500.0, 300.0, 780.0, 300.0),
        path(
            "M600 300 L800 300 L800 400 L1000 400 L1000 100 L600 100 Z",
            true,
        ),
        // 6: a line touching a later circle, 7, at its top.
        line(850.0, 550.0, 1050.0, 550.0),
        circle(950.0, 600.0, 50.0, true),
        // 8: a circle inside a larger later circle without a fill, 9; a
        // later filled circle, 10, inside it without touching its outline.
        circle(600.0, 600.0, 60.0, true),
        circle(600.0, 600.0, 120.0, false),
        circle(600.0, 600.0, 30.0, true),
    ]);
    for index in 0..page.objects.len() {
        assert!(whole(&page, index), "{index}");
    }
    assert_eq!(page.lines.len(), page.objects.len());
}

#[test]
fn a_closed_outline_is_joined_at_its_start_and_short_pieces_are_dropped() {
    // A small circle on the top side of a rectangle drawn before it: the
    // outline of the rectangle starts at its top left corner, and what is
    // left of it is one piece, from the circle around to the circle.
    let page = page(&[
        rect(100.0, 100.0, 200.0, 100.0, true),
        circle(200.0, 100.0, 20.0, true),
    ]);
    assert_eq!(
        pieces(&page, 0),
        [vec![
            ep(220.0, 100.0),
            ep(300.0, 100.0),
            ep(300.0, 200.0),
            ep(100.0, 200.0),
            ep(100.0, 100.0),
            ep(180.0, 100.0)
        ]]
    );
    // When its start is hidden nothing is joined: with later circles on its
    // top left and bottom right corners, two pieces are left.
    let page = self::page(&[
        rect(100.0, 100.0, 200.0, 100.0, true),
        circle(100.0, 100.0, 20.0, true),
        circle(300.0, 200.0, 20.0, true),
    ]);
    assert_eq!(
        pieces(&page, 0),
        [
            vec![ep(120.0, 100.0), ep(300.0, 100.0), ep(300.0, 180.0)],
            vec![ep(280.0, 200.0), ep(100.0, 200.0), ep(100.0, 120.0)]
        ]
    );
    // A piece shorter than half a unit is dropped, a longer one kept.
    let short = self::page(&[
        line(100.0, 100.0, 300.0, 100.0),
        rect(100.3, 50.0, 300.0, 100.0, true),
    ]);
    assert!(lines_of(&short.objects, 0).is_empty());
    let kept = self::page(&[
        line(100.0, 100.0, 300.0, 100.0),
        rect(100.6, 50.0, 300.0, 100.0, true),
    ]);
    assert_eq!(pieces(&kept, 0), [vec![ep(100.0, 100.0), ep(100.6, 100.0)]]);
    // A dot is hidden whole or kept whole: here inside a later rectangle,
    // twice, then in the box of a later circle but outside it.
    let dots = self::page(&[
        r##"<polyline points="150,150 150,150" fill="none" stroke="#2f3d4a" stroke-width="12"/>"##
            .to_owned(),
        path("M150 120 L150 120", false),
        path("M305 105 L305 105", false),
        rect(100.0, 100.0, 100.0, 100.0, true),
        circle(350.0, 150.0, 50.0, true),
    ]);
    assert_eq!(dots.objects[1].points.len(), 1);
    assert!(lines_of(&dots.objects, 0).is_empty());
    assert!(lines_of(&dots.objects, 1).is_empty());
    assert!(whole(&dots, 2));
}

#[test]
fn contours_hide_by_the_nonzero_rule_and_keep_what_lies_on_their_edges() {
    let page = page(&[
        // 0: in the pentagon at the heart of a star, which its edges wind
        // twice: inside by the nonzero rule, as SVG fills it.
        line(590.0, 400.0, 610.0, 400.0),
        // 1: across the top point of the star.
        line(560.0, 250.0, 640.0, 250.0),
        path("M600 200 L718 562 L410 338 L790 338 L482 562 Z", true),
        // 3: along the top side of a later step, then into it.
        line(100.0, 700.0, 500.0, 700.0),
        path(
            "M200 700 L400 700 L400 750 L600 750 L600 600 L200 600 Z",
            true,
        ),
    ]);
    assert!(lines_of(&page.objects, 0).is_empty());
    let star = &page.objects[2];
    assert!(depth(star, [600.0, 400.0]) > 50.0);
    // The top point, between x = 600 ∓ 118 · 50 / 362 at y = 250.
    let edge = 118.0 * 50.0 / 362.0;
    let cut = pieces(&page, 1);
    assert_eq!(cut.len(), 2);
    assert_eq!((cut[0][0], cut[1][1]), (ep(560.0, 250.0), ep(640.0, 250.0)));
    assert!(close(cut[0][1], (600.0 - edge, 250.0), 1e-4));
    assert!(close(cut[1][0], (600.0 + edge, 250.0), 1e-4));
    // On the side of the step the line is on its boundary, not inside:
    // only what goes on into the step is hidden.
    assert_eq!(pieces(&page, 3), [vec![ep(100.0, 700.0), ep(400.0, 700.0)]]);
}

#[test]
fn ellipses_are_outlined_every_three_units_with_their_four_extremes_exact() {
    // Corners, number of points and the bits of all of them, the bits
    // computed apart, in Python, with the same formulas in IEEE doubles.
    for (low, high, count, pin) in [
        ([200.0, 200.0], [400.0, 400.0], 212, 480_595_097_660),
        ([45.0, 45.0], [55.0, 55.0], 32, 71_168_950_272),
        ([123.0, 103.0], [247.0, 227.0], 132, 297_522_743_220),
        ([100.0, 100.0], [2100.0, 2100.0], 256, 586_501_850_988),
        ([300.0, 300.0], [900.0, 500.0], 256, 583_311_797_544),
    ] {
        let outline = ellipse_outline(low, high);
        assert_eq!(outline.len(), count);
        let centre = [(low[0] + high[0]) / 2.0, (low[1] + high[1]) / 2.0];
        assert_eq!(outline[0], [high[0], centre[1]]);
        assert_eq!(outline[count / 4], [centre[0], high[1]]);
        assert_eq!(outline[count / 2], [low[0], centre[1]]);
        assert_eq!(outline[3 * count / 4], [centre[0], low[1]]);
        let radius = [(high[0] - low[0]) / 2.0, (high[1] - low[1]) / 2.0];
        for p in &outline {
            assert!((0..2).all(|axis| low[axis] <= p[axis] && p[axis] <= high[axis]));
            let (u, v) = (
                (p[0] - centre[0]) / radius[0],
                (p[1] - centre[1]) / radius[1],
            );
            assert!((u * u + v * v - 1.0).abs() < 1e-6);
        }
        // No chord longer than three units, but where 256 points do not
        // reach.
        let longest = (0..count)
            .map(|i| {
                let (a, b) = (outline[i], outline[(i + 1) % count]);
                (a[0] - b[0]).hypot(a[1] - b[1])
            })
            .fold(0.0, f64::max);
        assert!(longest <= 3.0 || count == 256, "{longest}");
        assert_eq!(bits(outline), pin);
    }
}

#[test]
fn the_lines_of_a_page_are_the_same_bits_every_time() {
    for ((key, svg), page) in PAGES.iter().zip(pages().unwrap()) {
        for _ in 0..2 {
            let again = read_page(svg).unwrap();
            assert_eq!(again.lines.len(), page.lines.len(), "{key}");
            for (a, b) in again.lines.iter().zip(&page.lines) {
                assert_eq!(
                    (a.style, a.rgb, a.width.to_bits()),
                    (b.style, b.rgb, b.width.to_bits())
                );
                let bits = |line: &PageObject| {
                    line.points
                        .iter()
                        .map(|p| (p.x.to_bits(), p.y.to_bits()))
                        .collect::<Vec<_>>()
                };
                assert_eq!(bits(a), bits(b), "{key}");
            }
        }
    }
}

#[test]
fn every_page_loses_only_what_a_filled_element_drawn_after_it_hides() {
    for ((key, _), page) in PAGES.iter().zip(pages().unwrap()) {
        let mut lines = Vec::new();
        let mut cut = 0;
        for (index, object) in page.objects.iter().enumerate() {
            let later: Vec<&PageObject> = page.objects[index + 1..]
                .iter()
                .filter(|later| later.style.fill_enabled == 1)
                .collect();
            let deepest = |p: Point| {
                later
                    .iter()
                    .map(|later| depth(later, p))
                    .fold(f64::NEG_INFINITY, f64::max)
            };
            let samples = samples(object);
            if whole(page, index) {
                // Nothing of its outline goes into a later fill, but by the
                // chords of an ellipse.
                for &p in &samples {
                    assert!(deepest(p) <= 0.3, "{key} {index}: {p:?}");
                }
            } else {
                cut += 1;
                let cut_into = pieces(page, index);
                for piece in &cut_into {
                    assert!(piece.len() >= 2, "{key} {index}");
                    assert!(length(&points64(piece)) >= 0.5, "{key} {index}");
                    // What is left lies outside every later fill...
                    for p in samples_of_line(piece) {
                        assert!(deepest(p) <= 1e-3, "{key} {index}: {p:?}");
                    }
                }
                // ... and everything outside them is left.
                let cut_into: Vec<Vec<Point>> =
                    cut_into.iter().map(|piece| points64(piece)).collect();
                for &p in samples.iter().filter(|&&p| deepest(p) < -0.3) {
                    let near = cut_into.iter().any(|piece| {
                        piece
                            .windows(2)
                            .any(|pair| segment_distance(p, pair[0], pair[1]) <= 0.3)
                    });
                    assert!(near, "{key} {index}: {p:?} is lost");
                }
            }
            lines.extend(lines_of(&page.objects, index));
        }
        assert!(cut > 0, "{key}: every page has outlines under later shapes");
        // The lines of the page are those of its elements in their order, on
        // the sheet with their outline.
        assert_eq!(lines.len(), page.lines.len());
        for (line, expected) in lines.iter().zip(&page.lines) {
            assert_eq!(
                (line.style, line.rgb, line.width),
                (expected.style, expected.rgb, expected.width)
            );
            assert_eq!(line.points, expected.points);
            let half = line.width / 2.0;
            for p in &line.points {
                assert!(p.x - half >= 0.0 && p.y - half >= 0.0);
                assert!(p.x + half <= page.width as f32 && p.y + half <= page.height as f32);
            }
        }
    }
}

#[test]
fn the_chimney_and_the_ground_of_the_house_lose_what_the_file_paints_over() {
    let (index, page) = PAGES
        .iter()
        .zip(pages().unwrap())
        .enumerate()
        .find_map(|(id, ((key, _), page))| (*key == "maison").then_some((id, page)))
        .unwrap();
    assert_eq!(index, 7);
    // The chimney, a rectangle from 664,240 to 728,350, goes down into the
    // roof drawn after it, from y = 300: three sides of it are left, joined
    // across the start of its outline.
    assert_eq!(
        page.objects[19].points,
        [ep(664.0, 240.0), ep(728.0, 350.0)]
    );
    assert_eq!(
        pieces(page, 19),
        [vec![
            ep(664.0, 300.0),
            ep(664.0, 240.0),
            ep(728.0, 240.0),
            ep(728.0, 300.0)
        ]]
    );
    // The roof stays a rectangle: the walls under it only touch it.
    assert!(whole(page, 20) && whole(page, 21));
    // The top of the ground, y = 632, loses where the two lower bushes,
    // drawn after it, cross it; the third one stops above it.
    let ground = pieces(page, 0);
    assert_eq!(ground.len(), 2);
    // Half the chord of each bush at y = 632: radii 50 and 46, centres 38
    // and 34 above.
    let first_bush = (50.0f64 * 50.0 - 38.0 * 38.0).sqrt();
    let second_bush = (46.0f64 * 46.0 - 34.0 * 34.0).sqrt();
    assert_eq!(ground[0].len(), 2);
    assert!(close(ground[0][0], (188.0 + first_bush, 632.0), 1e-3));
    assert!(close(ground[0][1], (346.0 - second_bush, 632.0), 1e-3));
    assert!(close(ground[1][0], (346.0 + second_bush, 632.0), 1e-3));
    assert_eq!(
        ground[1][1..5],
        [
            ep(1140.0, 632.0),
            ep(1140.0, 750.0),
            ep(60.0, 750.0),
            ep(60.0, 632.0)
        ]
    );
    assert!(close(ground[1][5], (188.0 - first_bush, 632.0), 1e-3));
}

#[test]
fn a_page_whose_lines_do_not_fit_a_document_or_cost_too_much_is_refused() {
    let page = page(&[
        line(100.0, 500.0, 500.0, 500.0),
        rect(200.0, 400.0, 100.0, 200.0, true),
    ]);
    // Two pieces of two points, then the rectangle: three objects, six
    // points.
    let fits = Room {
        objects: 3,
        points: 6,
    };
    assert_eq!(clip_outlines(&page.objects, fits).unwrap().len(), 3);
    for (objects, points, why) in [
        (2, 6, TOO_MANY_OBJECTS),
        (3, 5, TOO_MANY_POINTS),
        (3, 3, TOO_MANY_POINTS),
    ] {
        let refused = clip_outlines(&page.objects, Room { objects, points });
        assert_eq!(refused.err(), Some(why), "{objects} {points}");
    }
    // A wave of curves under a filled lens drawn by the same curves: every
    // segment of the one lies in the box of the other and visits all its
    // edges.
    let wave = |pairs: usize, end: &str| {
        let mut d = String::from("M400 400 c");
        for _ in 0..pairs {
            d.push_str(" 0 300 300 300 300 0 0 -300 -300 -300 -300 0");
        }
        d.push_str(end);
        d
    };
    let svg = format!(
        "{HEAD}{}{}</svg>",
        path(&wave(200, ""), false),
        path(&wave(200, " z"), true)
    );
    assert!(svg.len() <= MAX_PAGE_BYTES);
    assert_eq!(read_page(&svg).err(), Some(TOO_COMPLEX));
    // A few pairs of the same cost little, and the wave, on the edges of the
    // lens, is not inside it.
    let svg = format!(
        "{HEAD}{}{}</svg>",
        path(&wave(2, ""), false),
        path(&wave(2, " z"), true)
    );
    assert!(whole(&read_page(&svg).unwrap(), 0));
}
